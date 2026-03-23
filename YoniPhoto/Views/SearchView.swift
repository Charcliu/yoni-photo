//
//  SearchView.swift
//  YoniPhoto
//
//  Created by 刘畅 on 2026/3/21.
//

import SwiftUI
import Photos

// MARK: - 布局模式

enum SearchLayoutMode {
    case list   // 列表模式
    case grid   // 3列网格模式
}

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @State private var isSelectionMode = false
    @State private var layoutMode: SearchLayoutMode = .list
    @State private var showEditView = false
    
    // 网格滑动选择状态
    @State private var isDragging = false
    @State private var dragSelectValue: Bool = true
    @State private var dragStartIndex: Int? = nil
    @State private var dragCurrentIndex: Int? = nil
    @State private var dragPrevIndex: Int? = nil     // 上一帧手指位置（用于往回滑动时取消选中）
    @State private var gridCellFrames: [CellFrameInfo] = []
    
    // 自动滚动
    @State private var autoScrollTimer: Timer? = nil
    @State private var dragLocationInScroll: CGPoint = .zero
    @State private var searchScrollViewHeight: CGFloat = 0
    
    private let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索栏
                searchBar
                
                // 选择模式工具栏
                if isSelectionMode {
                    selectionToolbar
                }
                
                // 结果列表/网格
                if viewModel.searchResults.isEmpty {
                    emptyStateView
                } else {
                    switch layoutMode {
                    case .list:
                        resultsList
                    case .grid:
                        resultsGrid
                    }
                }
            }
            .navigationTitle("搜索媒体")
            .toolbar { toolbarContent }
            .sheet(isPresented: $viewModel.showAlbumNameInput) {
                albumNameSheet
            }
            .sheet(isPresented: $showEditView) {
                let selectedVideos = viewModel.searchResults.filter { viewModel.selectedVideoIds.contains($0.id) }
                VideoEditView(selectedVideos: selectedVideos)
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
                TextField("搜索地点、内容、标签、场景...", text: $viewModel.searchQuery)
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
        HStack(spacing: 6) {
            Button("全选") { viewModel.selectAll() }
                .font(.caption)
            Button("清空") { viewModel.clearSelection() }
                .font(.caption)
                .foregroundColor(.red)
            Spacer()
            Text("已选 \(viewModel.selectedVideoIds.count) 个")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // 加入相册按钮
            Button {
                viewModel.loadExistingAlbums()
                viewModel.showAlbumNameInput = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "rectangle.stack.badge.plus").font(.caption)
                    Text("相册").font(.caption).fontWeight(.semibold)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .disabled(viewModel.selectedVideoIds.isEmpty)
            
            // 剪辑按钮
            Button {
                showEditView = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "scissors").font(.caption)
                    Text("剪辑").font(.caption).fontWeight(.semibold)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.purple)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .disabled(viewModel.selectedVideoIds.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }
    
    // MARK: - 结果列表（列表模式）
    
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
    
    // MARK: - 结果网格（3列模式）
    
    private var resultsGrid: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 2) {
                        ForEach(viewModel.searchResults) { video in
                            SearchGridCell(
                                video: video,
                                isSelected: viewModel.selectedVideoIds.contains(video.id),
                                isSelectionMode: isSelectionMode
                            ) {
                                if isSelectionMode {
                                    viewModel.toggleSelection(for: video.id)
                                }
                            }
                            .id(video.id)
                            .background(
                                GeometryReader { cellGeo in
                                    Color.clear
                                        .preference(
                                            key: CellFramePreferenceKey.self,
                                            value: [CellFrameInfo(id: video.id, frame: cellGeo.frame(in: .named("searchGridSpace")))]
                                        )
                                }
                            )
                        }
                    }
                    .coordinateSpace(name: "searchGridSpace")
                    .gesture(
                        isSelectionMode ?
                        DragGesture(minimumDistance: 5, coordinateSpace: .named("searchGridSpace"))
                            .onChanged { value in
                                dragLocationInScroll = value.location
                                
                                if !isDragging {
                                    isDragging = true
                                    if let startVideo = searchVideoAt(location: value.startLocation),
                                       let idx = viewModel.searchResults.firstIndex(where: { $0.id == startVideo.id }) {
                                        dragStartIndex = idx
                                        dragCurrentIndex = idx
                                        dragPrevIndex = idx
                                        dragSelectValue = !viewModel.selectedVideoIds.contains(startVideo.id)
                                    }
                                    startSearchAutoScroll(proxy: proxy, geoHeight: geo.size.height)
                                }
                                
                                if let currentVideo = searchVideoAt(location: value.location),
                                   let idx = viewModel.searchResults.firstIndex(where: { $0.id == currentVideo.id }) {
                                    if idx != dragCurrentIndex {
                                        dragPrevIndex = dragCurrentIndex
                                        dragCurrentIndex = idx
                                        applySearchRangeSelection()
                                    }
                                }
                            }
                            .onEnded { _ in
                                isDragging = false
                                dragStartIndex = nil
                                dragCurrentIndex = nil
                                dragPrevIndex = nil
                                stopSearchAutoScroll()
                            }
                        : nil
                    )
                    .onPreferenceChange(CellFramePreferenceKey.self) { frames in
                        gridCellFrames = frames
                    }
                }
                .background(
                    GeometryReader { scrollGeo in
                        Color.clear.onAppear {
                            searchScrollViewHeight = scrollGeo.size.height
                        }
                        .onChange(of: scrollGeo.size.height) { _, h in
                            searchScrollViewHeight = h
                        }
                    }
                )
            }
        }
    }
    
    // MARK: - 网格滑动选择辅助方法
    
    private func searchVideoAt(location: CGPoint) -> VideoItem? {
        guard let frame = gridCellFrames.first(where: { $0.frame.contains(location) }) else { return nil }
        return viewModel.searchResults.first(where: { $0.id == frame.id })
    }
    
    private func applySearchRangeSelection() {
        guard let startIdx = dragStartIndex, let currentIdx = dragCurrentIndex else { return }
        let colCount = 3
        let videos = viewModel.searchResults
        
        // 如果有上一帧位置，先把「缩回的范围」内的视频重置为未选中状态
        if let prevIdx = dragPrevIndex, prevIdx != currentIdx {
            let prevMax = max(startIdx, prevIdx)
            let curMax = max(startIdx, currentIdx)
            let prevMin = min(startIdx, prevIdx)
            let curMin = min(startIdx, currentIdx)
            
            if prevMax > curMax {
                for i in (curMax + 1)...prevMax {
                    let id = videos[i].id
                    if dragSelectValue { viewModel.selectedVideoIds.remove(id) }
                    else { viewModel.selectedVideoIds.insert(id) }
                }
            }
            if prevMin < curMin {
                for i in prevMin...(curMin - 1) {
                    let id = videos[i].id
                    if dragSelectValue { viewModel.selectedVideoIds.remove(id) }
                    else { viewModel.selectedVideoIds.insert(id) }
                }
            }
        }
        
        let minIdx = min(startIdx, currentIdx)
        let maxIdx = max(startIdx, currentIdx)
        let startRow = startIdx / colCount
        let startCol = startIdx % colCount
        let currentRow = currentIdx / colCount
        let currentCol = currentIdx % colCount
        let isForward = currentIdx >= startIdx
        
        // 先清除当前范围内所有选中状态
        for i in minIdx...maxIdx {
            let id = videos[i].id
            if dragSelectValue { viewModel.selectedVideoIds.remove(id) }
            else { viewModel.selectedVideoIds.insert(id) }
        }
        
        // 按苹果相册规则重新选中
        for i in minIdx...maxIdx {
            let row = i / colCount
            let col = i % colCount
            var shouldSelect: Bool
            
            if startRow == currentRow {
                let minCol = min(startCol, currentCol)
                let maxCol = max(startCol, currentCol)
                shouldSelect = col >= minCol && col <= maxCol
            } else if row == startRow {
                shouldSelect = isForward ? col >= startCol : col <= startCol
            } else if row == currentRow {
                shouldSelect = isForward ? col <= currentCol : col >= currentCol
            } else {
                shouldSelect = true
            }
            
            let id = videos[i].id
            if shouldSelect {
                if dragSelectValue { viewModel.selectedVideoIds.insert(id) }
                else { viewModel.selectedVideoIds.remove(id) }
            }
        }
    }
    
    private func startSearchAutoScroll(proxy: ScrollViewProxy, geoHeight: CGFloat) {
        stopSearchAutoScroll()
        searchScrollViewHeight = geoHeight
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            DispatchQueue.main.async {
                guard isDragging else { return }
                let threshold: CGFloat = 80
                let y = dragLocationInScroll.y
                let results = viewModel.searchResults
                
                if y > searchScrollViewHeight - threshold {
                    if let currentIdx = dragCurrentIndex {
                        let nextIdx = min(currentIdx + 3, results.count - 1)
                        withAnimation(.linear(duration: 0.1)) {
                            proxy.scrollTo(results[nextIdx].id, anchor: .bottom)
                        }
                    }
                } else if y < threshold {
                    if let currentIdx = dragCurrentIndex {
                        let prevIdx = max(currentIdx - 3, 0)
                        withAnimation(.linear(duration: 0.1)) {
                            proxy.scrollTo(results[prevIdx].id, anchor: .top)
                        }
                    }
                }
            }
        }
    }
    
    private func stopSearchAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }
    
    // MARK: - 空状态
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            if viewModel.searchQuery.isEmpty {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 56))
                    .foregroundColor(.secondary)
                    Text("暂无已分析的媒体")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    Text("前往「图库」选择媒体进行分析")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 56))
                    .foregroundColor(.secondary)
                    Text("没有找到相关媒体")
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
            HStack(spacing: 4) {
                // 布局切换按钮
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        layoutMode = layoutMode == .list ? .grid : .list
                    }
                } label: {
                    Image(systemName: layoutMode == .list ? "square.grid.3x3" : "list.bullet")
                        .font(.system(size: 16))
                }
                
                // 选择按钮
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
}

// MARK: - 搜索结果行（列表模式）

struct SearchResultRow: View {
    let video: VideoItem
    let isSelected: Bool
    let isSelectionMode: Bool
    let searchQuery: String
    let onTap: () -> Void
    
    var body: some View {
        Group {
            if isSelectionMode {
                rowContent
                    .contentShape(Rectangle())
                    .onTapGesture { onTap() }
            } else {
                NavigationLink(destination: VideoDetailView(video: video)) {
                    rowContent
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.blue.opacity(0.05) : Color.clear)
    }
    
    private var rowContent: some View {
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
                    if video.mediaType == .video {
                        Text(formatDuration(video.duration))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Capsule())
                            .padding(3)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Capsule())
                            .padding(3)
                    }
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
                
                // 地点信息
                if let locationName = video.locationName {
                    HStack(spacing: 3) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(locationName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
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
    }
}

// MARK: - 搜索结果网格单元格（3列模式）

struct SearchGridCell: View {
    let video: VideoItem
    let isSelected: Bool
    let isSelectionMode: Bool
    let onTap: () -> Void
    
    private let cellSize: CGFloat = (UIScreen.main.bounds.width - 4) / 3
    
    var body: some View {
        Group {
            if isSelectionMode {
                cardContent
                    .contentShape(Rectangle())
                    .onTapGesture { onTap() }
            } else {
                NavigationLink(destination: VideoDetailView(video: video)) {
                    cardContent
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
    
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 缩略图区域
            ZStack(alignment: .topLeading) {
                VideoThumbnailView(assetId: video.id, size: CGSize(width: cellSize, height: cellSize * 0.75))
                    .frame(width: cellSize, height: cellSize * 0.75)
                    .clipped()
                
                // 时长/类型标签（左下角）
                VStack {
                    Spacer()
                    HStack {
                        if video.mediaType == .video {
                            Text(formatDuration(video.duration))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Capsule())
                                .padding(4)
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Capsule())
                                .padding(4)
                        }
                        Spacer()
                    }
                }
                .frame(width: cellSize, height: cellSize * 0.75)
                
                // 选中遮罩
                if isSelectionMode {
                    Rectangle()
                        .fill(isSelected ? Color.blue.opacity(0.3) : Color.clear)
                        .frame(width: cellSize, height: cellSize * 0.75)
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundColor(isSelected ? .blue : .white)
                        .shadow(radius: 2)
                        .padding(6)
                }
            }
            
            // 分析结果信息
            VStack(alignment: .leading, spacing: 3) {
                // 标题
                Text(video.analysisResult?.title ?? video.filename)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // 标签
                if let tags = video.analysisResult?.tags, !tags.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(tags.prefix(2), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 9))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())
                        }
                    }
                } else if let summary = video.analysisResult?.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(width: cellSize, alignment: .leading)
        }
    }
}
