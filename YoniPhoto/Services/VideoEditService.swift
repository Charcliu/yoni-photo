
//
//  VideoEditService.swift
//  YoniPhoto
//
//  Created by 刘畅 on 2026/3/21.
//

import Foundation
import Photos
import AVFoundation
import UIKit

// MARK: - 剪辑脚本数据模型

/// AI 生成的单段剪辑指令
struct ClipInstruction: Codable, Identifiable {
    var id: String          // 对应 VideoItem.id（PHAsset localIdentifier）
    var startTime: Double   // 截取起始时间（秒）
    var endTime: Double     // 截取结束时间（秒）
    var reason: String      // AI 说明为什么选这段
    var order: Int          // 在最终视频中的顺序
}

/// AI 生成的完整剪辑方案
struct EditScript: Codable {
    var title: String               // 剪辑视频标题
    var description: String         // 剪辑思路说明
    var clips: [ClipInstruction]    // 各段剪辑指令（已按 order 排序）
    var totalDuration: Double       // 预计总时长（秒）
    var bgMusic: String?            // 背景音乐建议（歌曲名/风格）
    var bgMusicReason: String?      // 背景音乐推荐理由
}

// MARK: - 剪辑进度

enum EditProgress {
    case generatingScript           // AI 生成剪辑脚本中
    case loadingAssets(Int, Int)    // 加载视频资源（当前, 总数）
    case composing(Double)          // 合成中（0~1）
    case exporting(Double)          // 导出中（0~1）
    case done(URL)                  // 完成，输出文件 URL
    case failed(String)             // 失败
}

// MARK: - VideoEditService

class VideoEditService {
    static let shared = VideoEditService()
    private init() {}

    // 通义千问 API Key
    private var apiKey: String {
        UserDefaults.standard.string(forKey: "qwen_api_key") ?? ""
    }
    private let apiURL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"

    // MARK: - 主入口：AI 生成剪辑脚本

    /// 根据选中的 VideoItem 列表和用户想法，调用 AI 生成剪辑脚本
    func generateEditScript(for videos: [VideoItem], userIdea: String = "") async throws -> EditScript {
        guard !apiKey.isEmpty else {
            throw EditError.apiKeyMissing
        }
        guard !videos.isEmpty else {
            throw EditError.noVideosSelected
        }

        // 构建视频信息描述（供 AI 参考）
        // 使用简短的数字索引作为 ID，避免 AI 复制长字符串出错
        var videoDescriptions: [String] = []
        for (index, video) in videos.enumerated() {
            let shortId = "V\(index + 1)"  // 简短 ID，如 V1, V2, V3
            var desc = "[\(shortId)] 时长:\(formatDuration(video.duration))"
            if let loc = video.locationName { desc += "，地点:\(loc)" }
            if let date = video.creationDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                desc += "，拍摄时间:\(formatter.string(from: date))"
            }
            if let result = video.analysisResult {
                desc += "，标题:\(result.title)，摘要:\(result.summary)，场景:\(result.scene)，活动:\(result.activity)，情绪:\(result.mood)"
            }
            videoDescriptions.append(desc)
        }

        let videoListText = videoDescriptions.joined(separator: "\n")
        
        // 用户想法部分
        let ideaSection: String
        if userIdea.isEmpty {
            ideaSection = "请根据视频内容、情绪、场景，智能选取最精彩的片段，组合成一个流畅、有节奏感的短视频。"
        } else {
            ideaSection = """
            【用户剪辑需求（必须严格遵守）】：\(userIdea)
            你必须完全按照用户的需求来选取片段、安排顺序、推荐音乐，不能忽视用户的任何要求。
            """
        }

        let prompt = """
        你是一位专业的视频剪辑师。我有以下\(videos.count)段视频素材，请帮我生成一个自动剪辑方案：

        \(videoListText)

        \(ideaSection)

        要求：
        1. 每段视频选取最精彩的连续片段（startTime 到 endTime），不要超过原视频时长
        2. 按照故事逻辑或情绪节奏排列顺序
        3. 总时长控制在 30~120 秒之间
        4. 根据视频内容和用户想法，推荐一首合适的背景音乐（填写歌曲名或音乐风格，如「轻快旅行BGM」「周杰伦-稻香」等）
        5. clips 中每个片段的 "id" 字段必须使用素材列表中方括号内的编号（如 V1、V2），不要修改
        6. 严格按照以下 JSON 格式返回，不要有任何其他文字：

        {
          "title": "剪辑视频标题",
          "description": "剪辑思路说明（50字以内）",
          "bgMusic": "推荐背景音乐名称或风格",
          "bgMusicReason": "推荐理由（20字以内）",
          "clips": [
            {
              "id": "V1",
              "startTime": 0.0,
              "endTime": 10.0,
              "reason": "选取这段的原因",
              "order": 1
            }
          ],
          "totalDuration": 30.0
        }
        """

        let requestBody: [String: Any] = [
"model": "qwen-max",
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 2000,
            "temperature": 0.6
        ]

        guard let url = URL(string: apiURL) else {
            throw EditError.networkError("无效的API地址")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "未知错误"
            throw EditError.apiError("HTTP错误: \(errorMsg)")
        }

        return try parseScriptResponse(data, videos: videos)
    }

    // MARK: - 解析 AI 剪辑脚本响应

    private func parseScriptResponse(_ data: Data, videos: [VideoItem]) throws -> EditScript {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw EditError.parseError("无法解析 API 响应")
        }

        let jsonString = extractJSON(from: text)
        guard let jsonData = jsonString.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw EditError.parseError("无法解析剪辑脚本 JSON")
        }

        let title = dict["title"] as? String ?? "我的剪辑"
        let description = dict["description"] as? String ?? ""
        let totalDuration = dict["totalDuration"] as? Double ?? 0
        let bgMusic = dict["bgMusic"] as? String
        let bgMusicReason = dict["bgMusicReason"] as? String

        guard let clipsArray = dict["clips"] as? [[String: Any]] else {
            throw EditError.parseError("剪辑脚本中缺少 clips 字段")
        }

        // 构建简短 ID -> 真实 VideoItem 的映射
        var shortIdMap: [String: VideoItem] = [:]
        for (index, video) in videos.enumerated() {
            shortIdMap["V\(index + 1)"] = video
        }

        var clips: [ClipInstruction] = []
        for clipDict in clipsArray {
            guard let shortId = clipDict["id"] as? String else { continue }
            // 先用简短 ID 查找，再尝试原始 ID 兜底
            guard let video = shortIdMap[shortId] ?? videos.first(where: { $0.id == shortId }) else { continue }
            let id = video.id  // 使用真实的 PHAsset localIdentifier

            let startTime = clipDict["startTime"] as? Double ?? 0
            let endTime = min(clipDict["endTime"] as? Double ?? video.duration, video.duration)
            let reason = clipDict["reason"] as? String ?? ""
            let order = clipDict["order"] as? Int ?? clips.count + 1

            // 确保时间合法
            guard endTime > startTime else { continue }

            clips.append(ClipInstruction(
                id: id,
                startTime: max(0, startTime),
                endTime: endTime,
                reason: reason,
                order: order
            ))
        }

        // 按 order 排序
        clips.sort { $0.order < $1.order }

        guard !clips.isEmpty else {
            throw EditError.parseError("AI 未生成有效的剪辑片段")
        }

        return EditScript(title: title, description: description, clips: clips, totalDuration: totalDuration, bgMusic: bgMusic, bgMusicReason: bgMusicReason)
    }

    // MARK: - 执行视频合成

    /// 根据剪辑脚本合成视频，通过 progressHandler 回调进度
    func composeVideo(
        script: EditScript,
        progressHandler: @escaping (EditProgress) -> Void
    ) async throws -> URL {
        let clips = script.clips
        let total = clips.count

        // 1. 加载所有 AVAsset
        var avAssets: [(ClipInstruction, AVAsset)] = []
        for (index, clip) in clips.enumerated() {
            progressHandler(.loadingAssets(index + 1, total))
            guard let phAsset = PhotoLibraryService.shared.fetchAsset(withIdentifier: clip.id) else {
                throw EditError.assetLoadFailed("找不到视频: \(clip.id)")
            }
            guard let avAsset = await loadAVAsset(from: phAsset) else {
                throw EditError.assetLoadFailed("无法加载视频资源: \(clip.id)")
            }
            avAssets.append((clip, avAsset))
        }

        // 2. 构建 AVMutableComposition
        progressHandler(.composing(0))
        let composition = AVMutableComposition()

        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ),
        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw EditError.compositionFailed("无法创建合成轨道")
        }

        var currentTime = CMTime.zero
        // 收集每段视频轨道信息，用于后续构建 VideoComposition
        var videoTrackInfos: [(srcTrack: AVAssetTrack, timeRange: CMTimeRange, insertTime: CMTime)] = []

        for (index, (clip, avAsset)) in avAssets.enumerated() {
            let startCM = CMTime(seconds: clip.startTime, preferredTimescale: 600)
            let endCM = CMTime(seconds: clip.endTime, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: startCM, end: endCM)

            // 插入视频轨道
            if let srcVideoTrack = try? await avAsset.loadTracks(withMediaType: .video).first {
                try? videoTrack.insertTimeRange(timeRange, of: srcVideoTrack, at: currentTime)
                videoTrackInfos.append((srcTrack: srcVideoTrack, timeRange: timeRange, insertTime: currentTime))
            }

            // 插入音频轨道（可能没有音频，忽略错误）
            if let srcAudioTrack = try? await avAsset.loadTracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(timeRange, of: srcAudioTrack, at: currentTime)
            }

            let clipDuration = CMTime(seconds: clip.endTime - clip.startTime, preferredTimescale: 600)
            currentTime = CMTimeAdd(currentTime, clipDuration)

            progressHandler(.composing(Double(index + 1) / Double(avAssets.count)))
        }

        // 3. 构建 AVVideoComposition 修正视频方向（保持原始宽高比）
        let videoComposition = try await buildVideoComposition(for: composition, trackInfos: videoTrackInfos)

        // 4. 导出
        progressHandler(.exporting(0))
        let outputURL = try await exportComposition(composition, videoComposition: videoComposition, progressHandler: progressHandler)
        progressHandler(.done(outputURL))
        return outputURL
    }

    // MARK: - 构建 VideoComposition（修正方向）

    private func buildVideoComposition(
        for composition: AVMutableComposition,
        trackInfos: [(srcTrack: AVAssetTrack, timeRange: CMTimeRange, insertTime: CMTime)]
    ) async throws -> AVMutableVideoComposition {
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        // 计算所有片段中最大的自然尺寸（考虑旋转后的实际尺寸）
        var maxWidth: CGFloat = 0
        var maxHeight: CGFloat = 0

        // 先收集所有片段的实际渲染尺寸
        var renderSizes: [CGSize] = []
        for info in trackInfos {
            let naturalSize = try await info.srcTrack.load(.naturalSize)
            let transform = try await info.srcTrack.load(.preferredTransform)
            let renderSize = naturalSize.applying(transform)
            let absSize = CGSize(width: abs(renderSize.width), height: abs(renderSize.height))
            renderSizes.append(absSize)
            maxWidth = max(maxWidth, absSize.width)
            maxHeight = max(maxHeight, absSize.height)
        }

        // 使用第一个片段的尺寸作为输出尺寸（保持其宽高比）
        let outputSize: CGSize
        if let firstSize = renderSizes.first, firstSize.width > 0, firstSize.height > 0 {
            outputSize = firstSize
        } else {
            outputSize = CGSize(width: 1080, height: 1920)
        }
        videoComposition.renderSize = outputSize

        guard let compositionVideoTrack = composition.tracks(withMediaType: .video).first else {
            throw EditError.compositionFailed("找不到合成视频轨道")
        }

        // 为每个片段创建 instruction
        var instructions: [AVMutableVideoCompositionInstruction] = []
        for (index, info) in trackInfos.enumerated() {
            let naturalSize = try await info.srcTrack.load(.naturalSize)
            let transform = try await info.srcTrack.load(.preferredTransform)

            // 计算该片段在合成轨道中的实际时间范围
            let clipDuration = info.timeRange.duration
            let compositionTimeRange = CMTimeRange(start: info.insertTime, duration: clipDuration)

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = compositionTimeRange

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)

            // 计算变换：将视频旋转到正确方向，并缩放填充输出尺寸
            let finalTransform = calculateTransform(
                naturalSize: naturalSize,
                preferredTransform: transform,
                outputSize: outputSize
            )
            layerInstruction.setTransform(finalTransform, at: info.insertTime)

            instruction.layerInstructions = [layerInstruction]
            instructions.append(instruction)
            _ = index
        }

        videoComposition.instructions = instructions
        return videoComposition
    }

    /// 计算将视频正确旋转并缩放到目标尺寸的变换矩阵
    private func calculateTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        outputSize: CGSize
    ) -> CGAffineTransform {
        // 应用 preferredTransform 后的实际渲染尺寸
        let transformedSize = naturalSize.applying(preferredTransform)
        let actualWidth = abs(transformedSize.width)
        let actualHeight = abs(transformedSize.height)

        guard actualWidth > 0, actualHeight > 0 else { return preferredTransform }

        // 等比缩放，使视频填满输出尺寸（保持宽高比，居中裁剪）
        let scaleX = outputSize.width / actualWidth
        let scaleY = outputSize.height / actualHeight
        let scale = max(scaleX, scaleY) // 使用 max 保证填满，min 则保证完整显示

        // 先应用 preferredTransform（修正旋转），再缩放，再居中
        var t = preferredTransform
        t = t.scaledBy(x: scale, y: scale)

        // 计算居中偏移
        let scaledWidth = actualWidth * scale
        let scaledHeight = actualHeight * scale
        let tx = (outputSize.width - scaledWidth) / 2
        let ty = (outputSize.height - scaledHeight) / 2

        // 修正 preferredTransform 中已有的平移，加上居中偏移
        t.tx = preferredTransform.tx * scale + tx
        t.ty = preferredTransform.ty * scale + ty

        return t
    }

    // MARK: - 导出合成视频

    private func exportComposition(
        _ composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition,
        progressHandler: @escaping (EditProgress) -> Void
    ) async throws -> URL {
        // 输出到临时目录
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("yoni_edit_\(Int(Date().timeIntervalSince1970)).mp4")

        // 删除已存在的临时文件
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw EditError.exportFailed("无法创建导出会话")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition

        // 监听导出进度
        let progressTask = Task {
            while !Task.isCancelled {
                progressHandler(.exporting(Double(exportSession.progress)))
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            }
        }

        await exportSession.export()
        progressTask.cancel()

        switch exportSession.status {
        case .completed:
            return outputURL
        case .failed:
            throw EditError.exportFailed(exportSession.error?.localizedDescription ?? "导出失败")
        case .cancelled:
            throw EditError.exportFailed("导出已取消")
        default:
            throw EditError.exportFailed("导出状态异常")
        }
    }

    // MARK: - 保存到相册

    func saveToPhotoLibrary(url: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    // MARK: - 辅助方法

    private func loadAVAsset(from phAsset: PHAsset) async -> AVAsset? {
        return await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
    }

    private func extractJSON(from text: String) -> String {
        var cleaned = text
        if let start = cleaned.range(of: "```json") {
            cleaned = String(cleaned[start.upperBound...])
        } else if let start = cleaned.range(of: "```") {
            cleaned = String(cleaned[start.upperBound...])
        }
        if let end = cleaned.range(of: "```") {
            cleaned = String(cleaned[..<end.lowerBound])
        }
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}") {
            return String(cleaned[start...end])
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return minutes > 0 ? "\(minutes)分\(seconds)秒" : "\(seconds)秒"
    }
}

// MARK: - 错误类型

enum EditError: LocalizedError {
    case apiKeyMissing
    case noVideosSelected
    case networkError(String)
    case apiError(String)
    case parseError(String)
    case assetLoadFailed(String)
    case compositionFailed(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing: return "请先在设置中配置通义千问 API Key"
        case .noVideosSelected: return "请先选择要剪辑的视频"
        case .networkError(let msg): return "网络错误: \(msg)"
        case .apiError(let msg): return "API错误: \(msg)"
        case .parseError(let msg): return "解析错误: \(msg)"
        case .assetLoadFailed(let msg): return "视频加载失败: \(msg)"
        case .compositionFailed(let msg): return "视频合成失败: \(msg)"
        case .exportFailed(let msg): return "视频导出失败: \(msg)"
        }
    }
}
