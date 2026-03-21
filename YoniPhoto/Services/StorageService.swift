
//
//  StorageService.swift
//  YoniPhoto
//
//  Created by 刘畅 on 2026/3/21.
//

import Foundation

class StorageService {
    static let shared = StorageService()
    
    private let storageKey = "video_analysis_results"
    private var cache: [String: VideoItem] = [:]
    
    private init() {
        loadFromDisk()
    }
    
    // MARK: - 读取
    
    func getVideoItem(for assetId: String) -> VideoItem? {
        return cache[assetId]
    }
    
    func getAllAnalyzedItems() -> [VideoItem] {
        return cache.values.filter { $0.isAnalyzed }
    }
    
    func isAnalyzed(assetId: String) -> Bool {
        return cache[assetId]?.isAnalyzed ?? false
    }
    
    // MARK: - 写入
    
    func saveVideoItem(_ item: VideoItem) {
        cache[item.id] = item
        saveToDisk()
    }
    
    func saveVideoItems(_ items: [VideoItem]) {
        for item in items {
            cache[item.id] = item
        }
        saveToDisk()
    }
    
    func updateAnalysisResult(for assetId: String, result: VideoAnalysisResult) {
        guard var item = cache[assetId] else { return }
        item.analysisResult = result
        item.analysisStatus = .completed
        item.analysisDate = Date()
        cache[assetId] = item
        saveToDisk()
    }
    
    /// 分析完成后保存完整 VideoItem（包含 asset 元数据 + 分析结果）
    func saveAnalyzedItem(_ item: VideoItem) {
        cache[item.id] = item
        saveToDisk()
    }
    
    func updateAnalysisStatus(for assetId: String, status: AnalysisStatus) {
        guard var item = cache[assetId] else { return }
        item.analysisStatus = status
        cache[assetId] = item
        saveToDisk()
    }
    
    // MARK: - 搜索
    
    func search(query: String) -> [VideoItem] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return getAllAnalyzedItems()
        }
        let lowercasedQuery = query.lowercased()
        return getAllAnalyzedItems().filter { item in
            // 按 AI 分析内容搜索
            if let result = item.analysisResult,
               result.searchableText.lowercased().contains(lowercasedQuery) {
                return true
            }
            // 按拍摄地点搜索
            if let locationName = item.locationName,
               locationName.lowercased().contains(lowercasedQuery) {
                return true
            }
            return false
        }
    }
    
    // MARK: - 持久化
    
    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(cache)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("StorageService 保存失败: \(error)")
        }
    }
    
    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            cache = try JSONDecoder().decode([String: VideoItem].self, from: data)
        } catch {
            print("StorageService 加载失败: \(error)")
            cache = [:]
        }
    }
    
    // 清除所有数据（调试用）
    func clearAll() {
        cache = [:]
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
