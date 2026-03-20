
//
//  SearchView.swift
//  YoniPhoto
//
//  Created by 刘畅 on 2026/3/21.
//

import SwiftUI
import Photos

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @State private var isSelectionMode = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索栏
                searchBar
                
                // 选择模式工具栏
                if isSelectionMode {
                    selectionToolbar
                }
                
                // 结果列表
                if viewModel.searchResults.isEmpty {
                    emptyStateView
                } else {
                    resultsList
                }
            }
            .navigationTitle("搜索视频")
            .toolbar { toolbarContent }
            .sheet(isPresented: $viewModel.showAlbumNameInput) {
                albumNameSheet
            }
            .overlay(alignment: .top) {
                if let msg = viewModel.successMessage {
                    ToastView(message: msg, type: .success)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                viewModel.successMessage = nil
                            }
                        }
                }
                if let msg = viewModel.errorMessage {
                    ToastView(message: msg, type: .error)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                viewModel.errorMessage = nil
                            }
                        }
                }
            }
        }
        .onAppear {
            viewModel.loadAllAnalyzed()
        }
    }
    
    // MARK: - 搜索栏
    
    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索视频内容、标签、场景...", text: $viewModel.searchQuery)
                    .autocorrectionDisabled()
                    .onChange(of: viewModel.searchQuery) { _, _ in
                        viewModel.performSearch()
                    }
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                        viewModel.loadAllAnalyzed()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }
    
    // MARK: - 选择工具栏
    
    private var selectionToolbar: some View {
        HStack(spacing: 12) {
            Button("全选") { viewModel.selectAll() }
                .font(.subheadline)
            Button("清空") { viewModel.clearSelection() }
                .font(.subheadline)
                .foregroundColor(.red)
            Spacer()
            Text("已选 \(viewModel.selectedVideoIds.count) 个")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button {
                viewModel.loadExistingAlbums()
                viewModel.showAlbumNameInput = true
            } label: {
                Label("加入相册", systemImage: "rectangle.stack.badge.plus")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedVideoIds.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }
    
    // MARK: - 结果列表
    
    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.searchResults) { video in
                    SearchResultRow(
                        video: video,
                        isSelected: viewModel.selectedVideoIds.contains(video.id),
                        isSelectionMode: isSelectionMode,
                        searchQuery: viewModel.searchQuery
                    ) {
                        if isSelectionMode {
                            viewModel.toggleSelection(for: video.id)
                        }
                    }
                    Divider().padding(.leading, 80)
                }
            }
        }
    }
    
    // MARK: - 空状态
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            if viewModel.searchQuery.isEmpty {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 56))
                    .foregroundColor(.secondary)
                Text("暂无已分析的视频")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("前往「视频库」选择视频进行分析")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 56))
                    .foregroundColor(.secondary)
                Text("没有找到相关视频")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("尝试其他关键词，如：旅游、聚餐、运动...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
    
    // MARK: - 相册名称输入 Sheet
    
    private var albumNameSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // 新建相册
                VStack(alignment: .leading, spacing: 10) {
                    Text("新建相册")
                        .font(.headline)
                    TextField("输入相册名称", text: $viewModel.albumName)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    
                    Button {
                        Task {
                            await viewModel.addSelectedToAlbum(named: viewModel.albumName)
                        }
                    } label: {
                        Label("创建并添加", systemImage: "plus.rectangle.on.folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.albumName.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isAddingToAlbum)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // 已有相册
                if !viewModel.existingAlbums.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("添加到已有相册")
                            .font(.headline)
                        
                        ForEach(viewModel.existingAlbums, id: \.self) { albumName in
                            Button {
                                Task {
                                    await viewModel.addSelectedToAlbum(named: albumName)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "folder")
                                        .foregroundColor(.blue)
                                    Text(albumName)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("选择相册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") {
                        viewModel.showAlbumNameInput = false
                    }
                }
            }
            .overlay {
                if viewModel.isAddingToAlbum {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView("添加中...")
                        .padding(20)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isSelectionMode.toggle()
                if !isSelectionMode {
                    viewModel.clearSelection()
                }
            } label: {
                Text(isSelectionMode ? "完成" : "选择")
                    .fontWeight(isSelectionMode ? .semibold : .regular)
            }
        }
    }
}

// MARK: - 搜索结果行

struct SearchResultRow: View {
    let video: VideoItem
    let isSelected: Bool
    let isSelectionMode: Bool
    let searchQuery: String
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 选择框
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
            }
            
            // 缩略图
            VideoThumbnailView(assetId: video.id, size: CGSize(width: 64, height: 64))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottomTrailing) {
                    Text(formatDuration(video.duration))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.65))
                        .clipShape(Capsule())
                        .padding(3)
                }
            
            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(video.analysisResult?.title ?? video.filename)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                if let summary = video.analysisResult?.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // 标签
                if let tags = video.analysisResult?.tags, !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(tags.prefix(4), id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 10))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            if !isSelectionMode {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.blue.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                onTap()
            }
        }
        .background {
            if !isSelectionMode {
                NavigationLink(destination: VideoDetailView(video: video)) {
                    EmptyView()
                }
                .opacity(0)
            }
        }
    }
}
