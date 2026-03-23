
//
//  VideoLibraryView.swift
//  YoniPhoto
//
//  Created by 刘畅 on 2026/3/21.
//

import SwiftUI
import Photos

struct VideoLibraryView: View {
    @StateObject private var viewModel = VideoLibraryViewModel()
    
    // 滑动选择状态
    @State private var isDragging = false
    @State private var dragSelectValue: Bool = true  // 拖动时是选中还是取消选中
    @State private var dragStartIndex: Int? = nil    // 起始视频在 filteredVideos 中的索引
    @State private var dragCurrentIndex: Int? = nil  // 当前手指所在视频的索引
    @State private var dragPrevIndex: Int? = nil     // 上一帧手指所在视频的索引（用于往回滑动时取消选中）
    
    // 自动滚动
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var autoScrollTimer: Timer? = nil
    @State private var dragLocationInScroll: CGPoint = .zero  // 手指在 ScrollView 中的位置
    @State private var scrollViewHeight: CGFloat = 0
    
    // 筛选模式
    @State private var filterMode: FilterMode = .all
    
    enum FilterMode { case all, analyzed, unanalyzed }
    
    // 已分析视频重新分析弹窗
    @State private var showReanalyzeAlert = false
    @State private var analyzedSelectedCount = 0
    
    // AI 剪辑
    @State private var showEditView = false
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.authorizationStatus {
                case .authorized, .limited:
                    mainContent
                case .denied, .restricted:
                    permissionDeniedView
                case .notDetermined:
                    requestPermissionView
                @unknown default:
                    requestPermissionView
                }
            }
            .navigationTitle("图库")
            .toolbar { toolbarContent }
            .overlay(alignment: .bottom) {
                if viewModel.isAnalyzing {
                    analysisProgressBanner
                }
            }
            .overlay(alignment: .top) {
                if let msg = viewModel.successMessage {
                    ToastView(message: msg, type: .success)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                viewModel.successMessage = nil
                            }
                        }
                }
                if let msg = viewModel.errorMessage {
                    ToastView(message: msg, type: .error)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                                viewModel.errorMessage = nil
                            }
                        }
                }
            }
        .sheet(isPresented: $showEditView) {
            let selectedVideos = viewModel.allVideos.filter { viewModel.selectedVideoIds.contains($0.id) }
            VideoEditView(selectedVideos: selectedVideos)
        }
        .alert("部分媒体已分析", isPresented: $showReanalyzeAlert) {
                Button("跳过已分析，仅分析未分析") {
                    viewModel.analyzeSelectedVideos(skipAnalyzed: true)
                }
                Button("全部重新分析") {
                    viewModel.analyzeSelectedVideos(skipAnalyzed: false)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("已选媒体中有 \(analyzedSelectedCount) 个已分析过，是否重新分析？")
            }
        }
        .task {
            if viewModel.authorizationStatus == .authorized || viewModel.authorizationStatus == .limited {
                await viewModel.loadVideos()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await viewModel.refreshAuthorizationStatus() }
        }
    }
    
    // MARK: - 主内容
    
    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            // 统计栏（支持点击筛选）
            statsBar
            
            if viewModel.isLoading {
                Spacer()
                ProgressView("加载媒体中...")
                Spacer()
            } else if viewModel.allVideos.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("相册中没有媒体")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                // 选择模式工具栏
                if viewModel.isSelectionMode {
                    selectionToolbar
                }
                
                // 视频网格
                GeometryReader { geo in
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(Array(filteredVideos.enumerated()), id: \.element.id) { index, video in
                                    VideoGridCell(
                                        video: video,
                                        isSelected: viewModel.selectedVideoIds.contains(video.id),
                                        isSelectionMode: viewModel.isSelectionMode,
                                        isDragHighlighted: false
                                    ) {
                                        if viewModel.isSelectionMode {
                                            viewModel.toggleSelection(for: video.id)
                                        }
                                    }
                                    .id(video.id)
                                    .background(
                                        GeometryReader { cellGeo in
                                            Color.clear
                                                .preference(
                                                    key: CellFramePreferenceKey.self,
                                                    value: [CellFrameInfo(id: video.id, frame: cellGeo.frame(in: .named("gridSpace")))]
                                                )
                                        }
                                    )
                                }
                            }
                            .coordinateSpace(name: "gridSpace")
                            .gesture(
                                viewModel.isSelectionMode ?
                                DragGesture(minimumDistance: 5, coordinateSpace: .named("gridSpace"))
                                    .onChanged { value in
                                        // 记录手指在 ScrollView 坐标系中的位置（用于自动滚动判断）
                                        dragLocationInScroll = value.location
                                        
                                        if !isDragging {
                                            isDragging = true
                                            // 找到起始视频的索引
                                            if let startVideo = videoAt(location: value.startLocation),
                                               let idx = filteredVideos.firstIndex(where: { $0.id == startVideo.id }) {
                                                dragStartIndex = idx
                                                dragCurrentIndex = idx
                                                dragPrevIndex = idx
                                                dragSelectValue = !viewModel.selectedVideoIds.contains(startVideo.id)
                                            }
                                            startAutoScroll(proxy: proxy, geo: geo)
                                        }
                                        
                                        // 找到当前手指所在视频的索引
                                        if let currentVideo = videoAt(location: value.location),
                                           let idx = filteredVideos.firstIndex(where: { $0.id == currentVideo.id }) {
                                            if idx != dragCurrentIndex {
                                                dragPrevIndex = dragCurrentIndex
                                                dragCurrentIndex = idx
                                                applyRangeSelection()
                                            }
                                        }
                                    }
                                    .onEnded { _ in
                                        isDragging = false
                                        dragStartIndex = nil
                                        dragCurrentIndex = nil
                                        dragPrevIndex = nil
                                        stopAutoScroll()
                                    }
                                : nil
                            )
                            .onPreferenceChange(CellFramePreferenceKey.self) { frames in
                                viewModel.updateCellFrames(frames)
                            }
                        }
                        .background(
                            GeometryReader { scrollGeo in
                                Color.clear.onAppear {
                                    scrollViewHeight = scrollGeo.size.height
                                    scrollProxy = proxy
                                }
                                .onChange(of: scrollGeo.size.height) { _, h in
                                    scrollViewHeight = h
                                }
                            }
                        )
                    }
                }
            }
        }
    }
    
    /// 当前筛选后的视频列表
    private var filteredVideos: [VideoItem] {
        switch filterMode {
        case .all: return viewModel.allVideos
        case .analyzed: return viewModel.allVideos.filter { $0.isAnalyzed }
        case .unanalyzed: return viewModel.allVideos.filter { !$0.isAnalyzed }
        }
    }
    
    /// 根据坐标找到对应的视频（在 filteredVideos 中查找）
    private func videoAt(location: CGPoint) -> VideoItem? {
        guard let frame = viewModel.cellFrames.first(where: { $0.frame.contains(location) }) else { return nil }
        return filteredVideos.first(where: { $0.id == frame.id })
    }
    
    /// 苹果相册风格的区间选择：
    /// - 起始行：从起始列到行尾全选
    /// - 中间行：整行全选
    /// - 当前行：从行首到当前列全选
    /// - 往回滑动时，缩回范围外的视频自动取消选中
    private func applyRangeSelection() {
        guard let startIdx = dragStartIndex, let currentIdx = dragCurrentIndex else { return }
        let colCount = 3
        let videos = filteredVideos
        
        // 如果有上一帧位置，先把「缩回的范围」内的视频重置为未选中状态
        if let prevIdx = dragPrevIndex, prevIdx != currentIdx {
            let prevMin = min(startIdx, prevIdx)
            let prevMax = max(startIdx, prevIdx)
            let curMin = min(startIdx, currentIdx)
            let curMax = max(startIdx, currentIdx)
            
            // 找出上一帧范围比当前范围多出来的部分（缩回的区域）
            // 向下滑后往回：prevMax > curMax，需要清除 curMax+1 ~ prevMax
            if prevMax > curMax {
                for i in (curMax + 1)...prevMax {
                    let id = videos[i].id
                    if dragSelectValue { viewModel.selectedVideoIds.remove(id) }
                    else { viewModel.selectedVideoIds.insert(id) }
                }
            }
            // 向上滑后往回：prevMin < curMin，需要清除 prevMin ~ curMin-1
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
        
        // 先将当前范围内所有视频重置（清除之前的选择再重新计算）
        for i in minIdx...maxIdx {
            let id = videos[i].id
            if dragSelectValue {
                viewModel.selectedVideoIds.remove(id)
            } else {
                viewModel.selectedVideoIds.insert(id)
            }
        }
        
        // 按苹果相册规则选中区间内的视频
        let isForward = currentIdx >= startIdx  // 向下/向右滑动
        
        for i in minIdx...maxIdx {
            let row = i / colCount
            let col = i % colCount
            var shouldSelect: Bool
            
            if startRow == currentRow {
                // 同一行：选中起始列到当前列之间
                let minCol = min(startCol, currentCol)
                let maxCol = max(startCol, currentCol)
                shouldSelect = col >= minCol && col <= maxCol
            } else if row == startRow {
                // 起始行
                if isForward {
                    shouldSelect = col >= startCol  // 从起始列到行尾
                } else {
                    shouldSelect = col <= startCol  // 从行首到起始列
                }
            } else if row == currentRow {
                // 当前行
                if isForward {
                    shouldSelect = col <= currentCol  // 从行首到当前列
                } else {
                    shouldSelect = col >= currentCol  // 从当前列到行尾
                }
            } else {
                // 中间行：整行全选
                shouldSelect = true
            }
            
            let id = videos[i].id
            if shouldSelect {
                if dragSelectValue {
                    viewModel.selectedVideoIds.insert(id)
                } else {
                    viewModel.selectedVideoIds.remove(id)
                }
            }
        }
    }
    
    // MARK: - 自动滚动
    
    private func startAutoScroll(proxy: ScrollViewProxy, geo: GeometryProxy) {
        stopAutoScroll()
        scrollProxy = proxy
        scrollViewHeight = geo.size.height
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            DispatchQueue.main.async {
                guard isDragging else { return }
                let threshold: CGFloat = 80  // 距离边缘多少像素触发滚动
                let y = dragLocationInScroll.y
                
                // 接近底部：向下滚动到下一个视频
                if y > scrollViewHeight - threshold {
                    if let currentIdx = dragCurrentIndex {
                        let nextIdx = min(currentIdx + 3, filteredVideos.count - 1)
                        let nextId = filteredVideos[nextIdx].id
                        withAnimation(.linear(duration: 0.1)) {
                            proxy.scrollTo(nextId, anchor: .bottom)
                        }
                    }
                }
                // 接近顶部：向上滚动到上一个视频
                else if y < threshold {
                    if let currentIdx = dragCurrentIndex {
                        let prevIdx = max(currentIdx - 3, 0)
                        let prevId = filteredVideos[prevIdx].id
                        withAnimation(.linear(duration: 0.1)) {
                            proxy.scrollTo(prevId, anchor: .top)
                        }
                    }
                }
            }
        }
    }
    
    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }
    
    // MARK: - 统计栏
    
    private var statsBar: some View {
        HStack(spacing: 0) {
            filterStatButton(value: viewModel.totalCount, label: "全部", color: .primary, mode: .all)
            Divider().frame(height: 20)
            filterStatButton(value: viewModel.analyzedCount, label: "已分析", color: .green, mode: .analyzed)
            Divider().frame(height: 20)
            filterStatButton(value: viewModel.unanalyzedCount, label: "未分析", color: .orange, mode: .unanalyzed)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
    
    @ViewBuilder
    private func filterStatButton(value: Int, label: String, color: Color, mode: FilterMode) -> some View {
        let isActive = filterMode == mode
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                filterMode = (filterMode == mode) ? .all : mode
            }
        } label: {
            VStack(spacing: 2) {
                Text("\(value)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(isActive ? color : color.opacity(0.7))
                Text(label)
                    .font(.caption)
                    .foregroundColor(isActive ? color : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? color.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 选择工具栏
    
    private var selectionToolbar: some View {
        HStack(spacing: 6) {
            Button("全选") { viewModel.selectAll() }
                .font(.caption)
            Button("选未分析") { viewModel.selectUnanalyzed() }
                .font(.caption)
            Spacer()
            Text("已选 \(viewModel.selectedVideoIds.count) 个")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // 分析按钮
            Button {
                let analyzedCount = viewModel.selectedVideoIds.filter { id in
                    viewModel.allVideos.first(where: { $0.id == id })?.isAnalyzed ?? false
                }.count
                if analyzedCount > 0 {
                    analyzedSelectedCount = analyzedCount
                    showReanalyzeAlert = true
                } else {
                    viewModel.analyzeSelectedVideos(skipAnalyzed: true)
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "wand.and.stars").font(.caption)
                    Text("分析").font(.caption).fontWeight(.semibold)
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
    
    // MARK: - 分析进度条
    
    private var analysisProgressBanner: some View {
        VStack(spacing: 8) {
            HStack {
                Text(viewModel.analysisProgressText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Button("取消") {
                    viewModel.cancelAnalysis()
                }
                .font(.subheadline)
                .foregroundColor(.red)
            }
            ProgressView(value: viewModel.analysisProgress)
                .progressViewStyle(.linear)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .shadow(radius: 8)
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if viewModel.isSelectionMode {
                Button("完成") {
                    viewModel.toggleSelectionMode()
                }
                .fontWeight(.semibold)
            } else {
                HStack(spacing: 16) {
                    Button {
                        viewModel.analyzeAllUnanalyzed()
                    } label: {
                        Image(systemName: "wand.and.stars")
                    }
                    .disabled(viewModel.unanalyzedCount == 0 || viewModel.isAnalyzing)
                    
                    Button {
                        viewModel.toggleSelectionMode()
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                }
            }
        }
    }
    
    // MARK: - 权限视图
    
    private var requestPermissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            Text("需要相册访问权限")
                .font(.title2)
                .fontWeight(.bold)
            Text("请允许访问相册以读取和分析您的图片和视频")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("授权访问") {
                if viewModel.authorizationStatus == .notDetermined {
                    Task { await viewModel.requestPermissionAndLoad() }
                } else {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
    }
    
    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundColor(.red)
            Text("相册访问被拒绝")
                .font(.title2)
                .fontWeight(.bold)
            Text("请前往「设置 > 隐私与安全性 > 照片」开启访问权限")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("前往设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}

// MARK: - 单元格坐标 Preference

struct CellFrameInfo: Equatable {
    let id: String
    let frame: CGRect
}

struct CellFramePreferenceKey: PreferenceKey {
    static var defaultValue: [CellFrameInfo] = []
    static func reduce(value: inout [CellFrameInfo], nextValue: () -> [CellFrameInfo]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - 视频网格单元格

struct VideoGridCell: View {
    let video: VideoItem
    let isSelected: Bool
    let isSelectionMode: Bool
    let isDragHighlighted: Bool
    let onTap: () -> Void
    
    private let cellSize: CGFloat = (UIScreen.main.bounds.width - 4) / 3
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(destination: VideoDetailView(video: video)) {
                ZStack(alignment: .bottomLeading) {
                    VideoThumbnailView(assetId: video.id, size: CGSize(width: cellSize, height: cellSize))
                    
                    // 视频显示时长标签，图片显示图片图标
                    if video.mediaType == .video {
                        Text(formatDuration(video.duration))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                            .padding(4)
                    } else {
                        Image(systemName: "photo")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                            .padding(4)
                    }
                }
            }
            .simultaneousGesture(TapGesture().onEnded {
                if isSelectionMode { onTap() }
            })
            .disabled(isSelectionMode)
            .onTapGesture {
                if isSelectionMode { onTap() }
            }
            
            // 分析状态指示（选择模式下隐藏）
            if !isSelectionMode {
                if video.analysisStatus == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.green)
                        .background(Color.white.clipShape(Circle()))
                        .padding(4)
                } else if video.analysisStatus == .analyzing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(6)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                        .padding(4)
                } else if video.analysisStatus == .failed {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.red)
                        .background(Color.white.clipShape(Circle()))
                        .padding(4)
                }
            }
            
            // 选中遮罩
            if isSelectionMode {
                Rectangle()
                    .fill(isSelected ? Color.blue.opacity(0.3) : Color.clear)
                    .frame(width: cellSize, height: cellSize)
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? .blue : .white)
                    .shadow(radius: 2)
                    .padding(6)
            }
        }
        .frame(width: cellSize, height: cellSize)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode { onTap() }
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - 统计项

struct StatItem: View {
    let value: Int
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Toast 提示

enum ToastType { case success, error }

struct ToastView: View {
    let message: String
    let type: ToastType
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: type == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(type == .success ? .green : .red)
            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.top, 8)
        .shadow(radius: 4)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(), value: message)
    }
}
