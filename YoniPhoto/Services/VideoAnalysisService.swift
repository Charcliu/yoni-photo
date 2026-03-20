
//
//  VideoAnalysisService.swift
//  YoniPhoto
//
//  Created by 刘畅 on 2026/3/21.
//

import Foundation
import UIKit
import Photos

// AI分析服务 - 使用通义千问 VL API 分析视频帧
class VideoAnalysisService {
    static let shared = VideoAnalysisService()
    
    // 通义千问 API Key（存储在本地）
    private var apiKey: String {
        return UserDefaults.standard.string(forKey: "qwen_api_key") ?? ""
    }
    
    // 通义千问 API 地址（兼容 OpenAI 格式）
    private let apiURL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    
    private init() {}
    
    // MARK: - 主分析入口
    
    func analyzeVideo(asset: PHAsset) async throws -> VideoAnalysisResult {
        // 提取视频帧
        let frames = await PhotoLibraryService.shared.extractFrames(from: asset, count: 3)
        guard !frames.isEmpty else {
            throw AnalysisError.frameExtractionFailed
        }
        
        // 调用AI分析
        return try await analyzeFrames(frames, duration: asset.duration)
    }
    
    // MARK: - AI分析帧
    
    private func analyzeFrames(_ images: [UIImage], duration: TimeInterval) async throws -> VideoAnalysisResult {
        guard !apiKey.isEmpty else {
            throw AnalysisError.apiKeyMissing
        }
        
        let durationText = formatDuration(duration)
        let prompt = """
        请分析这段视频的截图（共\(images.count)帧，视频时长约\(durationText)），用中文回答，严格按照以下JSON格式返回，不要有任何其他文字：
        {
          "title": "简短的视频标题（10字以内）",
          "summary": "视频内容摘要（50字以内）",
          "tags": ["标签1", "标签2", "标签3"],
          "scene": "场景描述（如：室内/室外/自然风景/城市街道等）",
          "people": "人物描述（如：无人/一人/多人/儿童/成人等）",
          "activity": "活动描述（如：运动/聚餐/旅游/日常生活等）",
          "mood": "情绪氛围（如：欢乐/温馨/激烈/平静等）",
          "keywords": ["关键词1", "关键词2", "关键词3", "关键词4", "关键词5"]
        }
        """
        
        // 构建通义千问消息内容（OpenAI 兼容格式，支持多图）
        var contentItems: [[String: Any]] = [
            ["type": "text", "text": prompt]
        ]
        
        // 添加图片（base64 格式）
        for image in images {
            guard let data = image.jpegData(compressionQuality: 0.7) else { continue }
            let base64 = data.base64EncodedString()
            contentItems.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(base64)"
                ]
            ])
        }
        
        let requestBody: [String: Any] = [
            "model": "qwen-vl-max",
            "messages": [
                [
                    "role": "user",
                    "content": contentItems
                ]
            ],
            "max_tokens": 500,
            "temperature": 0.4
        ]
        
        guard let url = URL(string: apiURL) else {
            throw AnalysisError.networkError("无效的API地址")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60
        
        print("[通义千问] 请求URL: \(apiURL)")
        print("[通义千问] API Key 长度: \(apiKey.count)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalysisError.networkError("无效的响应")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "未知错误"
            throw AnalysisError.apiError("HTTP \(httpResponse.statusCode): \(errorMsg)")
        }
        
        return try parseResponse(data)
    }
    
    // MARK: - 解析响应
    
    private func parseResponse(_ data: Data) throws -> VideoAnalysisResult {
        // 通义千问响应格式（OpenAI 兼容）：choices[0].message.content
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw AnalysisError.parseError("无法解析通义千问 API 响应")
        }
        
        // 提取JSON内容（去除可能的markdown代码块）
        let jsonString = extractJSON(from: text)
        
        guard let jsonData = jsonString.data(using: .utf8),
              let resultDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw AnalysisError.parseError("无法解析分析结果JSON")
        }
        
        return VideoAnalysisResult(
            title: resultDict["title"] as? String ?? "未知视频",
            summary: resultDict["summary"] as? String ?? "",
            tags: resultDict["tags"] as? [String] ?? [],
            scene: resultDict["scene"] as? String ?? "",
            people: resultDict["people"] as? String ?? "",
            activity: resultDict["activity"] as? String ?? "",
            mood: resultDict["mood"] as? String ?? "",
            keywords: resultDict["keywords"] as? [String] ?? []
        )
    }
    
    private func extractJSON(from text: String) -> String {
        // 去除markdown代码块
        var cleaned = text
        if let start = cleaned.range(of: "```json") {
            cleaned = String(cleaned[start.upperBound...])
        } else if let start = cleaned.range(of: "```") {
            cleaned = String(cleaned[start.upperBound...])
        }
        if let end = cleaned.range(of: "```") {
            cleaned = String(cleaned[..<end.lowerBound])
        }
        // 提取{}之间的内容
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}") {
            return String(cleaned[start...end])
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)分\(seconds)秒"
        }
        return "\(seconds)秒"
    }
}

// MARK: - 错误类型

enum AnalysisError: LocalizedError {
    case apiKeyMissing
    case frameExtractionFailed
    case networkError(String)
    case apiError(String)
    case parseError(String)
    
    var errorDescription: String? {
        switch self {
        case .apiKeyMissing: return "请先在设置中配置通义千问 API Key"
        case .frameExtractionFailed: return "视频帧提取失败"
        case .networkError(let msg): return "网络错误: \(msg)"
        case .apiError(let msg): return "API错误: \(msg)"
        case .parseError(let msg): return "解析错误: \(msg)"
        }
    }
}
