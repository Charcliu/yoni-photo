
//
//  SearchViewModel.swift
//  YoniPhoto
//
//  Created by 刘畅 on 2026/3/21.
//

import Foundation
import Photos
import SwiftUI
import Combine

@MainActor
class SearchViewModel: ObservableObject {
    
    @Published var searchQuery = ""
    @Published var searchResults: [VideoItem] = []
    @Published var selectedVideoIds: Set<String> = []
    @Published var isAddingToAlbum = false
    @Published var albumName = ""
    @Published var showAlbumNameInput = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var existingAlbums: [String] = []
    
    private var searchTask: Task<Void, Never>?
    
    init() {
        loadAllAnalyzed()
    }
    
    // MARK: - 搜索
    
    func loadAllAnalyzed() {
        searchResults = StorageService.shared.getAllAnalyzedItems()
            .sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
    }
    
    func performSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 防抖 300ms
            if Task.isCancelled { return }
            
            let results = StorageService.shared.search(query: searchQuery)
            searchResults = results.sorted {
                ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
            }
        }
    }
    
    // MARK: - 选择
    
    func toggleSelection(for videoId: String) {
        if selectedVideoIds.contains(videoId) {
            selectedVideoIds.remove(videoId)
        } else {
            selectedVideoIds.insert(videoId)
        }
    }
    
    func selectAll() {
        selectedVideoIds = Set(searchResults.map { $0.id })
    }
    
    func clearSelection() {
        selectedVideoIds.removeAll()
    }
    
    // MARK: - 添加到相册
    
    func loadExistingAlbums() {
        let albums = PhotoLibraryService.shared.fetchUserAlbums()
        existingAlbums = albums.compactMap { $0.localizedTitle }
    }
    
    func addSelectedToAlbum(named name: String) async {
        guard !selectedVideoIds.isEmpty else {
            errorMessage = "请先选择视频"
            return
        }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "相册名称不能为空"
            return
        }
        
        isAddingToAlbum = true
        defer { isAddingToAlbum = false }
        
        do {
            try await PhotoLibraryService.shared.addAssets(
                Array(selectedVideoIds),
                toAlbum: name
            )
            successMessage = "✅ 已将 \(selectedVideoIds.count) 个视频添加到「\(name)」"
            selectedVideoIds.removeAll()
            showAlbumNameInput = false
            albumName = ""
        } catch {
            errorMessage = "添加失败: \(error.localizedDescription)"
        }
    }
}
