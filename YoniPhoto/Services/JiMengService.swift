//
//  JiMengService.swift
//  YoniPhoto
//
//  Created by 刘畅 on 2026/3/21.
//

import Foundation
import Photos
import AVFoundation
import UIKit
import CryptoKit

// MARK: - 即梦AI视频生成服务（火山引擎 VisualAI）

class JiMengService {
    static let shared = JiMengService()
    private init() {}

    // 火山引擎 Access Key ID
    var accessKeyId: String {
        UserDefaults.standard.string(forKey: "jimeng_access_key_id") ?? ""
    }

    // 火山引擎 Secret Access Key
    var secretAccessKey: String {
        UserDefaults.standard.string(forKey: "jimeng_secret_access_key") ?? ""
    }

    // 火山引擎即梦AI API 地址
    private let host = "visual.volcengineapi.com"
    private let region = "cn-north-1"
    private let service = "cv"

    // MARK: - 生成进度回调

    enum GenerateProgress {
        case extractingFrames           // 提取视频帧
        case uploadingImage             // 上传参考图
        case submitting                 // 提交生成任务
        case generating(Double)         // 生成中（0~1 估算进度）
        case downloading                // 下载生成的视频
        case done(URL)                  // 完成
        case failed(String)             // 失败
    }

    // MARK: - 主入口：根据视频+描述生成新视频

    func generateVideo(
        from videos: [VideoItem],
        description: String,
        progressHandler: @escaping (GenerateProgress) -> Void
    ) async throws -> URL {
        guard !accessKeyId.isEmpty, !secretAccessKey.isEmpty else {
            throw JiMengError.apiKeyMissing
        }
        guard !videos.isEmpty else {
            throw JiMengError.noVideosSelected
        }

        // 1. 从第一个视频提取关键帧作为参考图
        progressHandler(.extractingFrames)
        let referenceImage = try await extractKeyFrame(from: videos[0])

        // 2. 将图片转为 Base64
        progressHandler(.uploadingImage)
        guard let imageData = referenceImage.jpegData(compressionQuality: 0.85) else {
            throw JiMengError.uploadFailed("图片压缩失败")
        }
        let imageBase64 = imageData.base64EncodedString()

        // 3. 构建提示词
        let prompt = buildPrompt(videos: videos, userDescription: description)

        // 4. 提交图生视频任务
        progressHandler(.submitting)
        let taskId = try await submitImageToVideoTask(prompt: prompt, imageBase64: imageBase64)

        // 5. 轮询任务状态
        let videoURL = try await pollTaskResult(taskId: taskId, progressHandler: progressHandler)

        // 6. 下载视频到本地
        progressHandler(.downloading)
        let localURL = try await downloadVideo(from: videoURL)

        progressHandler(.done(localURL))
        return localURL
    }

    // MARK: - 提取视频关键帧

    private func extractKeyFrame(from video: VideoItem) async throws -> UIImage {
        guard let phAsset = PhotoLibraryService.shared.fetchAsset(withIdentifier: video.id) else {
            throw JiMengError.assetLoadFailed("找不到视频资源")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { avAsset, _, _ in
                guard let avAsset = avAsset else {
                    continuation.resume(throwing: JiMengError.assetLoadFailed("无法加载视频"))
                    return
                }

                let generator = AVAssetImageGenerator(asset: avAsset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 1280, height: 720)

                // 取视频中间帧
                let duration = avAsset.duration
                let midTime = CMTime(seconds: duration.seconds / 2, preferredTimescale: 600)

                do {
                    let cgImage = try generator.copyCGImage(at: midTime, actualTime: nil)
                    continuation.resume(returning: UIImage(cgImage: cgImage))
                } catch {
                    do {
                        let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
                        continuation.resume(returning: UIImage(cgImage: cgImage))
                    } catch {
                        continuation.resume(throwing: JiMengError.assetLoadFailed("无法提取视频帧"))
                    }
                }
            }
        }
    }

    // MARK: - 构建提示词

    private func buildPrompt(videos: [VideoItem], userDescription: String) -> String {
        var contextParts: [String] = []
        for video in videos.prefix(3) {
            if let result = video.analysisResult {
                contextParts.append("\(result.title)：\(result.summary)")
            }
        }
        let context = contextParts.isEmpty ? "" : "参考素材：\(contextParts.joined(separator: "；"))。"
        let desc = userDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        if desc.isEmpty {
            return "\(context)根据参考图片，生成一段流畅自然的短视频，保持原有风格和氛围。"
        } else {
            return "\(context)\(desc)"
        }
    }

    // MARK: - 提交图生视频任务（火山引擎即梦AI）

    private func submitImageToVideoTask(prompt: String, imageBase64: String) async throws -> String {
        let action = "CVSync2AsyncSubmitTask"
        let version = "2022-08-31"

        let body: [String: Any] = [
            "req_key": "jimeng_ti2v_v30_pro",
            "prompt": prompt,
            "binary_data_base64": [imageBase64],
            "frames": 121,
            "seed": -1
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let request = try buildSignedRequest(action: action, version: version, bodyData: bodyData)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JiMengError.apiError("网络请求失败")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JiMengError.apiError("响应解析失败，原始响应：\(String(data: data, encoding: .utf8) ?? "")")
        }

        // 优先判断外层 code，code=10000 才算请求成功
        let code = json["code"] as? Int ?? -1
        guard code == 10000 else {
            let errMsg = json["message"] as? String ?? "请求失败(code:\(code), HTTP:\(httpResponse.statusCode))"
            throw JiMengError.apiError(errMsg)
        }

        // 解析 task_id（在 data 字段下）
        if let respData = json["data"] as? [String: Any],
           let taskId = respData["task_id"] as? String {
            return taskId
        }

        throw JiMengError.apiError("无法获取任务ID，响应：\(String(data: data, encoding: .utf8) ?? "")")
    }

    // MARK: - 轮询任务结果

    private func pollTaskResult(
        taskId: String,
        progressHandler: @escaping (GenerateProgress) -> Void
    ) async throws -> URL {
        let action = "CVSync2AsyncGetResult"
        let version = "2022-08-31"
        let maxAttempts = 60  // 最多等待5分钟（每5秒一次）
        var attempts = 0

        while attempts < maxAttempts {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            attempts += 1

            let estimatedProgress = min(0.1 + Double(attempts) / Double(maxAttempts) * 0.8, 0.9)
            progressHandler(.generating(estimatedProgress))

            let body: [String: Any] = [
                "req_key": "jimeng_ti2v_v30_pro",
                "task_id": taskId
            ]
            let bodyData = try JSONSerialization.data(withJSONObject: body)

            guard let request = try? buildSignedRequest(action: action, version: version, bodyData: bodyData),
                  let (data, _) = try? await URLSession.shared.data(for: request),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // 优先判断外层 code，code=10000 才算请求成功
            let code = json["code"] as? Int ?? -1
            guard code == 10000 else {
                let errMsg = json["message"] as? String ?? "请求失败(code:\(code))"
                throw JiMengError.apiError(errMsg)
            }

            guard let taskData = json["data"] as? [String: Any] else {
                continue
            }

            // status 是字符串：in_queue / generating / done / not_found / expired
            let status = taskData["status"] as? String ?? ""
            switch status {
            case "done":
                // 成功，video_url 直接在 data 下
                if let urlStr = taskData["video_url"] as? String,
                   let videoURL = URL(string: urlStr) {
                    return videoURL
                }
                throw JiMengError.apiError("任务完成但无法获取视频URL，响应：\(String(data: data, encoding: .utf8) ?? "")")

            case "not_found":
                throw JiMengError.apiError("任务未找到，可能已过期，请重新提交")

            case "expired":
                throw JiMengError.apiError("任务已过期，请重新提交")

            default:
                // in_queue / generating，继续等待
                continue
            }
        }

        throw JiMengError.timeout("视频生成超时，请稍后重试")
    }

    // MARK: - 下载视频到本地

    private func downloadVideo(from remoteURL: URL) async throws -> URL {
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jimeng_\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: localURL)

        let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw JiMengError.downloadFailed("视频下载失败")
        }

        try FileManager.default.moveItem(at: tempURL, to: localURL)
        return localURL
    }

    // MARK: - 火山引擎 HMAC-SHA256 签名

    private func buildSignedRequest(action: String, version: String, bodyData: Data) throws -> URLRequest {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStr = dateFormatter.string(from: now)

        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let datetimeStr = dateFormatter.string(from: now)

        let urlStr = "https://\(host)/?Action=\(action)&Version=\(version)"
        guard let url = URL(string: urlStr) else {
            throw JiMengError.apiError("URL构建失败")
        }

        // 计算 body hash
        let bodyHash = SHA256.hash(data: bodyData).map { String(format: "%02x", $0) }.joined()

        // 构建 canonical request（headers 必须按字母序排列）
        let canonicalHeaders = "content-type:application/json\nhost:\(host)\nx-date:\(datetimeStr)\n"
        let signedHeaders = "content-type;host;x-date"
        let canonicalRequest = [
            "POST",
            "/",
            "Action=\(action)&Version=\(version)",
            canonicalHeaders,
            signedHeaders,
            bodyHash
        ].joined(separator: "\n")

        // 构建 string to sign
        let credentialScope = "\(dateStr)/\(region)/\(service)/request"
        let canonicalRequestHash = SHA256.hash(data: canonicalRequest.data(using: .utf8)!)
            .map { String(format: "%02x", $0) }.joined()
        let stringToSign = "HMAC-SHA256\n\(datetimeStr)\n\(credentialScope)\n\(canonicalRequestHash)"

        // 计算签名
        let signingKey = try deriveSigningKey(secretKey: secretAccessKey, date: dateStr, region: region, service: service)
        let signature = HMAC<SHA256>.authenticationCode(
            for: stringToSign.data(using: .utf8)!,
            using: signingKey
        ).map { String(format: "%02x", $0) }.joined()

        // 构建 Authorization header
        let authorization = "HMAC-SHA256 Credential=\(accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(datetimeStr, forHTTPHeaderField: "X-Date")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue(String(bodyData.count), forHTTPHeaderField: "Content-Length")
        request.httpBody = bodyData
        request.timeoutInterval = 30
        return request
    }

    private func deriveSigningKey(secretKey: String, date: String, region: String, service: String) throws -> SymmetricKey {
        let kDate = HMAC<SHA256>.authenticationCode(
            for: date.data(using: .utf8)!,
            using: SymmetricKey(data: secretKey.data(using: .utf8)!)
        )
        let kRegion = HMAC<SHA256>.authenticationCode(
            for: region.data(using: .utf8)!,
            using: SymmetricKey(data: Data(kDate))
        )
        let kService = HMAC<SHA256>.authenticationCode(
            for: service.data(using: .utf8)!,
            using: SymmetricKey(data: Data(kRegion))
        )
        let kSigning = HMAC<SHA256>.authenticationCode(
            for: "request".data(using: .utf8)!,
            using: SymmetricKey(data: Data(kService))
        )
        return SymmetricKey(data: Data(kSigning))
    }
}

// MARK: - 错误类型

enum JiMengError: LocalizedError {
    case apiKeyMissing
    case noVideosSelected
    case assetLoadFailed(String)
    case uploadFailed(String)
    case apiError(String)
    case downloadFailed(String)
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing: return "请先在设置中配置即梦AI的 Access Key ID 和 Secret Access Key"
        case .noVideosSelected: return "请先选择要参考的视频"
        case .assetLoadFailed(let msg): return "视频加载失败: \(msg)"
        case .uploadFailed(let msg): return "图片处理失败: \(msg)"
        case .apiError(let msg): return msg
        case .downloadFailed(let msg): return msg
        case .timeout(let msg): return msg
        }
    }
}
