
//
//  VideoDetailView.swift
//  YoniPhoto
//
//  Created by 刘畅 on 2026/3/21.
//

import SwiftUI
import Photos

struct VideoDetailView: View {
    let video: VideoItem
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 封面图
                VideoThumbnailView(assetId: video.id, size: CGSize(width: UIScreen.main.bounds.width, height: 240))
                    .overlay(alignment: .bottomTrailing) {
                        Text(formatDuration(video.duration))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                            .padding(10)
                    }
                
                VStack(alignment: .leading, spacing: 16) {
                    // 基本信息
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            AnalysisStatusBadge(status: video.analysisStatus)
                            Spacer()
                            if let date = video.creationDate {
                                Text(date, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text(video.analysisResult?.title ?? video.filename)
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    
                    Divider()
                    
                    if let result = video.analysisResult {
                        // 摘要
                        InfoSection(title: "内容摘要", icon: "doc.text") {
                            Text(result.summary)
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        
                        // 标签
                        if !result.tags.isEmpty {
                            InfoSection(title: "标签", icon: "tag") {
                                FlowLayout(spacing: 8) {
                                    ForEach(result.tags, id: \.self) { tag in
                                        TagChip(text: tag, color: .blue)
                                    }
                                }
                            }
                        }
                        
                        // 详细信息
                        InfoSection(title: "视频详情", icon: "info.circle") {
                            VStack(spacing: 10) {
                                DetailRow(label: "场景", value: result.scene, icon: "location")
                                DetailRow(label: "人物", value: result.people, icon: "person")
                                DetailRow(label: "活动", value: result.activity, icon: "figure.walk")
                                DetailRow(label: "氛围", value: result.mood, icon: "heart")
                            }
                        }
                        
                        // 关键词
                        if !result.keywords.isEmpty {
                            InfoSection(title: "搜索关键词", icon: "magnifyingglass") {
                                FlowLayout(spacing: 8) {
                                    ForEach(result.keywords, id: \.self) { keyword in
                                        TagChip(text: keyword, color: .purple)
                                    }
                                }
                            }
                        }
                        
                        // 分析时间
                        if let analysisDate = video.analysisDate {
                            Text("分析于 \(analysisDate, style: .relative)前")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 8)
                        }
                        
                    } else {
                        // 未分析状态
                        VStack(spacing: 12) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("该视频尚未分析")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("返回视频库，选中该视频后点击「分析」")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("视频详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 子组件

struct InfoSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            content()
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
        }
    }
}

struct TagChip: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

// 流式布局（标签换行）
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                height += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
