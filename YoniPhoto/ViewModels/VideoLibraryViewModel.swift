
//
//  VideoLibraryViewModel.swift
//  YoniPhoto
//
//  Created by 刘畅 on 2026/3/21.
//

import Foundation
import Photos
import SwiftUI
import Combine
import CoreLocation

@MainActor
class VideoLibraryViewModel: ObservableObject {
    
    // MARK: - Published 属性
    
    @Published var allVideos: [VideoItem] = []
    @Published var searchText: String = ""
    @Published var isLoading = false
    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0
    @Published var analysisProgressText = ""
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var selectedVideoIds: Set<String> = []
    @Published var isSelectionMode = false
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    
    // 滑动选择用：记录每个单元格的坐标
    var cellFrames: [CellFrameInfo] = []
    
    func updateCellFrames(_ frames: [CellFrameInfo]) {
        cellFrames = frames
    }
    
    // 搜索过滤结果
    var filteredVideos: [VideoItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return allVideos }
        let lower = trimmed.lowercased()
        return allVideos.filter { video in
            // 按地点搜索
            if let loc = video.locationName, loc.lowercased().contains(lower) { return true }
            // 按 AI 分析内容搜索
            if let result = video.analysisResult, result.searchableText.lowercased().contains(lower) { return true }
            // 按文件名搜索
            if video.filename.lowercased().contains(lower) { return true }
            return false
        }
    }
    
    // 分析队列控制
    private var analysisTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 初始化
    
    init() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        // 订阅 Service 的权限状态变化，保持同步
        PhotoLibraryService.shared.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .assign(to: \.authorizationStatus, on: self)
            .store(in: &cancellables)
    }
    
    // MARK: - 权限与加载
    
    func requestPermissionAndLoad() async {
        let status = await PhotoLibraryService.shared.requestAuthorization()
        authorizationStatus = status
        if status == .authorized || status == .limited {
            await loadVideos()
        }
    }
    
    func refreshAuthorizationStatus() async {
        let newStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorizationStatus = newStatus
        if newStatus == .authorized || newStatus == .limited {
            if allVideos.isEmpty {
                await loadVideos()
            }
        }
    }
    
    func loadVideos() async {
        isLoading = true
        defer { isLoading = false }
        
        let assets = PhotoLibraryService.shared.fetchAllVideos()
        
        var items: [VideoItem] = []
        for asset in assets {
            // 从本地存储恢复已分析的数据
            if let saved = StorageService.shared.getVideoItem(for: asset.localIdentifier) {
                items.append(saved)
            } else {
                let newItem = VideoItem(asset: asset)
                items.append(newItem)
            }
        }
        
        allVideos = items
        
        // 异步为没有地点信息的视频反地理编码
        Task { await resolveLocationsIfNeeded(for: assets) }
    }
    
    // MARK: - 地点反地理编码
    
    private func resolveLocationsIfNeeded(for assets: [PHAsset]) async {
        let geocoder = CLGeocoder()
        for asset in assets {
            guard let location = asset.location else { continue }
            // 已有地点信息则跳过
            if let existing = StorageService.shared.getVideoItem(for: asset.localIdentifier),
               existing.locationName != nil { continue }
            
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                if let placemark = placemarks.first {
                    var parts: [String] = []
                    if let country = placemark.country { parts.append(country) }
                    if let adminArea = placemark.administrativeArea { parts.append(adminArea) }
                    if let locality = placemark.locality { parts.append(locality) }
                    if let subLocality = placemark.subLocality { parts.append(subLocality) }
                    let locationName = parts.isEmpty ? nil : parts.joined(separator: " · ")
                    updateLocationName(assetId: asset.localIdentifier, locationName: locationName)
                }
            } catch {
                // 反地理编码失败，忽略
            }
            // 避免频繁请求 geocoder（苹果限制每秒1次）
            try? await Task.sleep(nanoseconds: 1_100_000_000)
        }
    }
    
    private func updateLocationName(assetId: String, locationName: String?) {
        if let index = allVideos.firstIndex(where: { $0.id == assetId }) {
            allVideos[index].locationName = locationName
            StorageService.shared.saveVideoItem(allVideos[index])
        }
    }
    
    // MARK: - 选择模式
    
    func toggleSelectionMode() {
        isSelectionMode.toggle()
        if !isSelectionMode {
            selectedVideoIds.removeAll()
        }
    }
    
    func toggleSelection(for videoId: String) {
        if selectedVideoIds.contains(videoId) {
            selectedVideoIds.remove(videoId)
        } else {
            selectedVideoIds.insert(videoId)
        }
    }
    
    func selectAll() {
        selectedVideoIds = Set(allVideos.map { $0.id })
    }
    
    func selectUnanalyzed() {
        selectedVideoIds = Set(allVideos.filter { !$0.isAnalyzed }.map { $0.id })
    }
    
    // MARK: - 批量分析
    
    func analyzeSelectedVideos(skipAnalyzed: Bool = true) {
        guard !selectedVideoIds.isEmpty else {
            errorMessage = "请先选择要分析的视频"
            return
        }
        
        let idsToAnalyze: [String]
        if skipAnalyzed {
            idsToAnalyze = selectedVideoIds.filter { id in
                !(allVideos.first(where: { $0.id == id })?.isAnalyzed ?? false)
            }
        } else {
            idsToAnalyze = Array(selectedVideoIds)
        }
        
        if idsToAnalyze.isEmpty {
            successMessage = "所选视频均已分析完成"
            return
        }
        
        analysisTask = Task {
            await performAnalysis(for: idsToAnalyze)
        }
    }
    
    func analyzeAllUnanalyzed() {
        let unanalyzedIds = allVideos.filter { !$0.isAnalyzed }.map { $0.id }
        guard !unanalyzedIds.isEmpty else {
            successMessage = "所有视频均已分析完成"
            return
        }
        analysisTask = Task {
            await performAnalysis(for: unanalyzedIds)
        }
    }
    
    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        analysisProgressText = "已取消"
    }
    
    private func performAnalysis(for assetIds: [String]) async {
        isAnalyzing = true
        analysisProgress = 0
        let total = assetIds.count
        var completed = 0
        var failed = 0
        
        for assetId in assetIds {
            if Task.isCancelled { break }
            
            analysisProgressText = "正在分析 \(completed + 1)/\(total)..."
            
            // 更新状态为分析中
            updateVideoStatus(assetId: assetId, status: .analyzing)
            
            guard let asset = PhotoLibraryService.shared.fetchAsset(withIdentifier: assetId) else {
                updateVideoStatus(assetId: assetId, status: .failed)
                failed += 1
                completed += 1
                analysisProgress = Double(completed) / Double(total)
                continue
            }
            
            do {
                let result = try await VideoAnalysisService.shared.analyzeVideo(asset: asset)
                
                // 更新本地列表
                if let index = allVideos.firstIndex(where: { $0.id == assetId }) {
                    var updated = allVideos[index]
                    updated.analysisResult = result
                    updated.analysisStatus = .completed
                    updated.analysisDate = Date()
                    allVideos[index] = updated
                    // 保存完整 VideoItem（含 asset 元数据）到持久化存储
                    StorageService.shared.saveAnalyzedItem(allVideos[index])
                }
                
            } catch {
                updateVideoStatus(assetId: assetId, status: .failed)
                failed += 1
                let errMsg = error.localizedDescription
                print("分析失败 \(assetId): \(errMsg)")
                // 记录最后一次错误信息，用于最终展示
                errorMessage = errMsg
            }
            
            completed += 1
            analysisProgress = Double(completed) / Double(total)
        }
        
        isAnalyzing = false
        isSelectionMode = false
        selectedVideoIds.removeAll()
        
        if failed == 0 {
            errorMessage = nil
            successMessage = "✅ 成功分析 \(completed) 个视频"
        } else if completed - failed == 0 {
            // 全部失败：errorMessage 已在 catch 里设置了具体原因，不覆盖
            // 如果 errorMessage 为空（理论上不会），才用兜底文案
            if errorMessage == nil {
                errorMessage = "分析失败，请检查 API Key 是否正确或网络是否可用"
            }
        } else {
            successMessage = "完成：\(completed - failed) 成功，\(failed) 失败"
        }
        analysisProgressText = ""
    }
    
    private func updateVideoStatus(assetId: String, status: AnalysisStatus) {
        StorageService.shared.updateAnalysisStatus(for: assetId, status: status)
        if let index = allVideos.firstIndex(where: { $0.id == assetId }) {
            allVideos[index].analysisStatus = status
        }
    }
    
    // MARK: - 统计
    
    var analyzedCount: Int { allVideos.filter { $0.isAnalyzed }.count }
    var unanalyzedCount: Int { allVideos.filter { !$0.isAnalyzed }.count }
    var totalCount: Int { allVideos.count }
}
