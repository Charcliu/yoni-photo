
//
//  VideoEditView.swift
//  YoniPhoto
//
//  Created by 刘畅 on 2026/3/21.
//

import SwiftUI
import AVKit
import Photos

// MARK: - 剪辑状态

enum EditState: Equatable {
    case inputIdea                  // 输入剪辑想法
    case generatingScript           // AI 生成脚本中
    case loadingAssets(Int, Int)    // 加载视频资源
    case composing(Double)          // 合成中
    case exporting(Double)          // 导出中
    case preview(URL, EditScript)   // 预览
    case saving                     // 保存中
    case saved                      // 已保存
    case failed(String)             // 失败

    static func == (lhs: EditState, rhs: EditState) -> Bool {
        switch (lhs, rhs) {
        case (.inputIdea, .inputIdea), (.generatingScript, .generatingScript),
             (.saving, .saving), (.saved, .saved): return true
        case (.loadingAssets(let a, let b), .loadingAssets(let c, let d)): return a == c && b == d
        case (.composing(let a), .composing(let b)): return a == b
        case (.exporting(let a), .exporting(let b)): return a == b
        case (.preview(let a, _), .preview(let b, _)): return a == b
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - VideoEditView

struct VideoEditView: View {
    let selectedVideos: [VideoItem]
    @Environment(\.dismiss) private var dismiss

    @State private var editState: EditState = .inputIdea
    @State private var editScript: EditScript? = nil
    @State private var outputURL: URL? = nil
    @State private var player: AVPlayer? = nil
    @State private var showScriptDetail = false
    @State private var saveSuccessMessage: String? = nil
    @State private var videoAspectRatio: CGFloat = 9/16  // 默认竖版
    
    // 剪辑想法输入
    @State private var userIdea: String = ""
    @FocusState private var ideaFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                switch editState {
                case .inputIdea:
                    inputIdeaView
                case .generatingScript, .loadingAssets, .composing, .exporting:
                    progressView
                case .preview(let url, let script):
                    previewView(url: url, script: script)
                case .saving:
                    savingView
                case .saved:
                    savedView
                case .failed(let msg):
                    failedView(message: msg)
                }
            }
            .navigationTitle("AI 自动剪辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .overlay(alignment: .top) {
                if let msg = saveSuccessMessage {
                    ToastView(message: msg, type: .success)
                        .padding(.top, 8)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                saveSuccessMessage = nil
                            }
                        }
                }
            }
        }
        .onDisappear {
            player?.pause()
        }
    }

    // MARK: - 输入剪辑想法页

    private var inputIdeaView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 顶部图标
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.1))
                            .frame(width: 80, height: 80)
                        Image(systemName: "scissors")
                            .font(.system(size: 36))
                            .foregroundColor(.purple)
                    }
                    Text("告诉 AI 你的剪辑想法")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("AI 将根据你的描述和视频内容，自动生成剪辑方案")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)

                // 输入框
                VStack(alignment: .leading, spacing: 8) {
                    Text("剪辑想法（可选）")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                        
                        if userIdea.isEmpty {
                            Text("例如：制作一个旅行回忆短片，突出风景和欢乐时刻，节奏轻快...")
                                .font(.subheadline)
                                .foregroundColor(Color(.placeholderText))
                                .padding(12)
                                .allowsHitTesting(false)
                        }
                        
                        TextEditor(text: $userIdea)
                            .font(.subheadline)
                            .focused($ideaFieldFocused)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(minHeight: 120)
                    }
                    .frame(minHeight: 120)
                    
                    // 快捷想法标签
                    Text("快速选择")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    FlowLayout(spacing: 8) {
                        ForEach(quickIdeas, id: \.self) { idea in
                            Button {
                                userIdea = idea
                                ideaFieldFocused = false
                            } label: {
                                Text(idea)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(userIdea == idea ? Color.purple.opacity(0.15) : Color(.tertiarySystemBackground))
                                    .foregroundColor(userIdea == idea ? .purple : .primary)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(userIdea == idea ? Color.purple.opacity(0.4) : Color.clear, lineWidth: 1)
                                    )
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)

                // 素材预览
                VStack(alignment: .leading, spacing: 8) {
                    Text("已选 \(selectedVideos.count) 段素材")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selectedVideos) { video in
                                VideoMiniCard(video: video)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                // 开始剪辑按钮
                Button {
                    ideaFieldFocused = false
                    startEditing(idea: userIdea)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                        Text("开始 AI 剪辑")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .onTapGesture {
            ideaFieldFocused = false
        }
    }
    
    private let quickIdeas = [
        "旅行回忆短片",
        "欢乐聚会集锦",
        "节奏感强的卡点视频",
        "温馨家庭时光",
        "运动精彩瞬间",
        "美食探店记录",
        "突出最精彩片段",
        "按时间顺序剪辑"
    ]

    // MARK: - 开始剪辑

    private func startEditing(idea: String) {
        editState = .generatingScript
        Task {
            do {
                // 1. AI 生成剪辑脚本（传入用户想法）
                let script = try await VideoEditService.shared.generateEditScript(
                    for: selectedVideos,
                    userIdea: idea.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                editScript = script

                // 2. 合成视频
                let url = try await VideoEditService.shared.composeVideo(script: script) { progress in
                    DispatchQueue.main.async {
                        switch progress {
                        case .loadingAssets(let cur, let total):
                            editState = .loadingAssets(cur, total)
                        case .composing(let p):
                            editState = .composing(p)
                        case .exporting(let p):
                            editState = .exporting(p)
                        case .done(let url):
                            outputURL = url
                            let newPlayer = AVPlayer(url: url)
                            newPlayer.actionAtItemEnd = .none
                            NotificationCenter.default.addObserver(
                                forName: .AVPlayerItemDidPlayToEndTime,
                                object: newPlayer.currentItem,
                                queue: .main
                            ) { _ in
                                newPlayer.seek(to: .zero)
                                newPlayer.play()
                            }
                            player = newPlayer
                        case .failed(let msg):
                            editState = .failed(msg)
                        default:
                            break
                        }
                    }
                }
                // 读取实际视频宽高比（在 Task 中异步执行）
                let asset = AVAsset(url: url)
                if let track = try? await asset.loadTracks(withMediaType: .video).first {
                    let size = try? await track.load(.naturalSize)
                    let transform = try? await track.load(.preferredTransform)
                    if let size = size, let transform = transform {
                        let transformed = size.applying(transform)
                        let w = abs(transformed.width)
                        let h = abs(transformed.height)
                        await MainActor.run {
                            if w > 0 && h > 0 {
                                videoAspectRatio = w / h
                            }
                            editState = .preview(url, script)
                        }
                    } else {
                        await MainActor.run {
                            editState = .preview(url, script)
                        }
                    }
                } else {
                    await MainActor.run {
                        editState = .preview(url, script)
                    }
                }
            } catch {
                await MainActor.run {
                    editState = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - 保存到相册

    private func saveToAlbum() {
        guard let url = outputURL else { return }
        editState = .saving
        Task {
            do {
                try await VideoEditService.shared.saveToPhotoLibrary(url: url)
                await MainActor.run {
                    editState = .saved
                }
            } catch {
                await MainActor.run {
                    editState = .failed("保存失败: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - 进度视图

    private var progressView: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 100, height: 100)
                Image(systemName: progressIcon)
                    .font(.system(size: 44))
                    .foregroundColor(.purple)
                    .symbolEffect(.pulse)
            }

            VStack(spacing: 8) {
                Text(progressTitle)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(progressSubtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if case .composing(let p) = editState {
                progressBar(value: p, label: "合成中")
            } else if case .exporting(let p) = editState {
                progressBar(value: p, label: "导出中")
            }

            selectedVideosSummary

            Spacer()
        }
        .padding(24)
    }

    private func progressBar(value: Double, label: String) -> some View {
        VStack(spacing: 6) {
            ProgressView(value: value)
                .progressViewStyle(.linear)
                .tint(.purple)
                .frame(maxWidth: 280)
            Text("\(label) \(Int(value * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var progressIcon: String {
        switch editState {
        case .generatingScript: return "brain.head.profile"
        case .loadingAssets: return "arrow.down.circle"
        case .composing: return "film.stack"
        case .exporting: return "square.and.arrow.up"
        default: return "scissors"
        }
    }

    private var progressTitle: String {
        switch editState {
        case .generatingScript: return "AI 正在分析视频..."
        case .loadingAssets(let cur, let total): return "加载视频 \(cur)/\(total)"
        case .composing: return "合成视频中..."
        case .exporting: return "导出视频中..."
        default: return ""
        }
    }

    private var progressSubtitle: String {
        switch editState {
        case .generatingScript:
            let idea = userIdea.trimmingCharacters(in: .whitespacesAndNewlines)
            return idea.isEmpty ? "正在根据视频内容生成最佳剪辑方案" : "正在根据你的想法「\(idea.prefix(20))」生成剪辑方案"
        case .loadingAssets: return "正在加载视频资源"
        case .composing: return "正在按剪辑方案拼接视频片段"
        case .exporting: return "正在导出高质量视频"
        default: return ""
        }
    }

    private var selectedVideosSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("共 \(selectedVideos.count) 段素材")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(selectedVideos) { video in
                        VideoMiniCard(video: video)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - 预览视图

    private func previewView(url: URL, script: EditScript) -> some View {
        VStack(spacing: 0) {
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(videoAspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .onAppear { player.play() }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(script.title)
                            .font(.title3)
                            .fontWeight(.bold)
                        Text(script.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        HStack(spacing: 12) {
                            Label("\(script.clips.count) 个片段", systemImage: "film.stack")
                            Label(formatDuration(script.totalDuration), systemImage: "clock")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        // 背景音乐推荐
                        if let bgMusic = script.bgMusic, !bgMusic.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "music.note")
                                    .foregroundColor(.purple)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("推荐背景音乐：\(bgMusic)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.purple)
                                    if let reason = script.bgMusicReason, !reason.isEmpty {
                                        Text(reason)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.purple.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    DisclosureGroup(
                        isExpanded: $showScriptDetail,
                        content: {
                            VStack(spacing: 8) {
                                ForEach(Array(script.clips.enumerated()), id: \.offset) { index, clip in
                                    ClipDetailRow(index: index + 1, clip: clip, videos: selectedVideos)
                                }
                            }
                            .padding(.top, 8)
                        },
                        label: {
                            Text("查看剪辑方案")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    )
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 100)
            }

            Spacer()
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 12) {
                // 重新剪辑 → 回到输入页
                Button {
                    player?.pause()
                    editState = .inputIdea
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("重新剪辑")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .foregroundColor(.primary)

                Button {
                    saveToAlbum()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                        Text("保存到相册")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .background(
                LinearGradient(
                    colors: [Color(.systemGroupedBackground).opacity(0), Color(.systemGroupedBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 100)
                .allowsHitTesting(false),
                alignment: .top
            )
        }
    }

    // MARK: - 保存中 / 保存成功 / 失败

    private var savingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView().scaleEffect(1.5)
            Text("正在保存到相册...")
                .font(.title3).fontWeight(.medium)
            Spacer()
        }
    }

    private var savedView: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle().fill(Color.green.opacity(0.1)).frame(width: 100, height: 100)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56)).foregroundColor(.green)
            }
            Text("已保存到相册").font(.title2).fontWeight(.bold)
            Text("你可以在相册中找到这段剪辑视频")
                .font(.subheadline).foregroundColor(.secondary)
            Button("完成") { dismiss() }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Spacer()
        }
        .padding(32)
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle().fill(Color.red.opacity(0.1)).frame(width: 100, height: 100)
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 56)).foregroundColor(.red)
            }
            Text("剪辑失败").font(.title2).fontWeight(.bold)
            Text(message)
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            HStack(spacing: 12) {
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered).controlSize(.large)
                Button("重新描述") { editState = .inputIdea }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            Spacer()
        }
        .padding(32)
    }

    // MARK: - 辅助

    private func formatDuration(_ duration: Double) -> String {
        let total = Int(duration)
        let minutes = total / 60
        let seconds = total % 60
        return minutes > 0 ? "\(minutes)分\(seconds)秒" : "\(seconds)秒"
    }
}

// MARK: - 流式布局（快捷标签用）

// MARK: - 视频小卡片（进度页用）

struct VideoMiniCard: View {
    let video: VideoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VideoThumbnailView(assetId: video.id, size: CGSize(width: 72, height: 72))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            if let result = video.analysisResult {
                Text(result.title)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: 72)
            }
        }
    }
}

// MARK: - 剪辑片段详情行

struct ClipDetailRow: View {
    let index: Int
    let clip: ClipInstruction
    let videos: [VideoItem]

    private var video: VideoItem? {
        videos.first(where: { $0.id == clip.id })
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.caption).fontWeight(.bold).foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Color.purple).clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(video?.analysisResult?.title ?? video?.filename ?? "视频\(index)")
                    .font(.subheadline).fontWeight(.medium).lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.caption2)
                    Text("\(formatTime(clip.startTime)) → \(formatTime(clip.endTime))（\(formatDuration(clip.endTime - clip.startTime))）")
                        .font(.caption).foregroundColor(.secondary)
                }

                Text(clip.reason)
                    .font(.caption).foregroundColor(.secondary).lineLimit(2)
            }

            Spacer()
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let m = total / 60, s = total % 60
        return m > 0 ? "\(m):\(String(format: "%02d", s))" : "0:\(String(format: "%02d", s))"
    }

    private func formatDuration(_ duration: Double) -> String {
        let total = Int(duration)
        let m = total / 60, s = total % 60
        return m > 0 ? "\(m)分\(s)秒" : "\(s)秒"
    }
}
