
//
//  VideoItem.swift
//  YoniPhoto
//
//  Created by 刘畅 on 2026/3/21.
//

import Foundation
import Photos

// 视频分析状态
enum AnalysisStatus: String, Codable {
    case notAnalyzed = "未分析"
    case analyzing = "分析中"
    case completed = "已完成"
    case failed = "分析失败"
}

// 视频数据模型
struct VideoItem: Identifiable, Codable {
    let id: String              // PHAsset localIdentifier
    let filename: String
    let duration: TimeInterval
    let creationDate: Date?
    let modificationDate: Date?
    
    var analysisStatus: AnalysisStatus
    var analysisResult: VideoAnalysisResult?
    var analysisDate: Date?
    var locationName: String?   // 反地理编码地名（国家·省·市·区）
    
    // 是否已分析
    var isAnalyzed: Bool {
        return analysisStatus == .completed && analysisResult != nil
    }
    
    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.filename = (asset.value(forKey: "filename") as? String) ?? "未知文件"
        self.duration = asset.duration
        self.creationDate = asset.creationDate
        self.modificationDate = asset.modificationDate
        self.analysisStatus = .notAnalyzed
        self.analysisResult = nil
        self.analysisDate = nil
        self.locationName = nil
    }
}

// 视频分析结果
struct VideoAnalysisResult: Codable {
    var title: String           // AI生成的标题
    var summary: String         // 内容摘要
    var tags: [String]          // 标签列表
    var scene: String           // 场景描述（室内/室外/自然等）
    var people: String          // 人物描述
    var activity: String        // 活动描述
    var mood: String            // 情绪/氛围
    var keywords: [String]      // 搜索关键词
    
    // 所有可搜索文本的合集
    var searchableText: String {
        let parts = [title, summary, scene, people, activity, mood] + tags + keywords
        return parts.joined(separator: " ")
    }
}
