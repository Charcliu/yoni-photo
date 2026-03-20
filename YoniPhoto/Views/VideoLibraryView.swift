
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
    @State private var showAPIKeyAlert = false
    @State private var apiKeyInput = ""
    
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
            .navigationTitle("视频库")
            .toolbar { toolbarContent }
            .overlay(alignment: .bottom) {
                if viewModel.isAnalyzing {
                    analysisProgressBanner
                }
            }
            .alert("API Key 设置", isPresented: $showAPIKeyAlert) {
                TextField("输入 Gemini API Key（AIza...）", text: $apiKeyInput)
                    .autocorrectionDisabled()
                Button("保存") {
                    UserDefaults.standard.set(apiKeyInput, forKey: "gemini_api_key")
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("请输入您的 Gemini API Key 以启用视频内容分析功能")
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
        }
        .task {
            // 仅在已授权时自动加载，权限请求由用户点击"授权访问"按钮主动触发
            if viewModel.authorizationStatus == .authorized || viewModel.authorizationStatus == .limited {
                await viewModel.loadVideos()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // 用户从系统设置返回后，重新检测权限状态
            Task { await viewModel.refreshAuthorizationStatus() }
        }
    }
    
    // MARK: - 主内容
    
    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            // 统计栏
            statsBar
            
            if viewModel.isLoading {
                Spacer()
                ProgressView("加载视频中...")
                Spacer()
            } else if viewModel.allVideos.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("相册中没有视频")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                // 选择模式工具栏
                if viewModel.isSelectionMode {
                    selectionToolbar
                }
                
                // 视频网格
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(viewModel.allVideos) { video in
                            VideoGridCell(
                                video: video,
                                isSelected: viewModel.selectedVideoIds.contains(video.id),
                                isSelectionMode: viewModel.isSelectionMode
                            ) {
                                if viewModel.isSelectionMode {
                                    viewModel.toggleSelection(for: video.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 统计栏
    
    private var statsBar: some View {
        HStack(spacing: 16) {
            StatItem(value: viewModel.totalCount, label: "全部", color: .primary)
            Divider().frame(height: 20)
            StatItem(value: viewModel.analyzedCount, label: "已分析", color: .green)
            Divider().frame(height: 20)
            StatItem(value: viewModel.unanalyzedCount, label: "未分析", color: .orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
    
    // MARK: - 选择工具栏
    
    private var selectionToolbar: some View {
        HStack(spacing: 12) {
            Button("全选") { viewModel.selectAll() }
                .font(.subheadline)
            Button("选未分析") { viewModel.selectUnanalyzed() }
                .font(.subheadline)
            Spacer()
            Text("已选 \(viewModel.selectedVideoIds.count) 个")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button {
                viewModel.analyzeSelectedVideos()
            } label: {
                Label("分析", systemImage: "wand.and.stars")
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
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showAPIKeyAlert = true
                apiKeyInput = UserDefaults.standard.string(forKey: "gemini_api_key") ?? ""
            } label: {
                Image(systemName: "key")
            }
        }
        
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
            Text("请允许访问相册以读取和分析您的视频")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("授权访问") {
                if viewModel.authorizationStatus == .notDetermined {
                    // 首次请求：弹出系统授权弹窗
                    Task { await viewModel.requestPermissionAndLoad() }
                } else {
                    // 已拒绝或受限：跳转系统设置
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

// MARK: - 视频网格单元格

struct VideoGridCell: View {
    let video: VideoItem
    let isSelected: Bool
    let isSelectionMode: Bool
    let onTap: () -> Void
    
    private let cellSize: CGFloat = (UIScreen.main.bounds.width - 4) / 3
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(destination: VideoDetailView(video: video)) {
                ZStack(alignment: .bottomLeading) {
                    VideoThumbnailView(assetId: video.id, size: CGSize(width: cellSize, height: cellSize))
                    
                    // 时长标签
                    Text(formatDuration(video.duration))
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
            .simultaneousGesture(TapGesture().onEnded {
                if isSelectionMode { onTap() }
            })
            .disabled(isSelectionMode)
            .onTapGesture {
                if isSelectionMode { onTap() }
            }
            
            // 分析状态指示
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
