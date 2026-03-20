
//
//  VideoThumbnailView.swift
//  YoniPhoto
//
//  Created by 刘畅 on 2026/3/21.
//

import SwiftUI
import Photos

// 视频缩略图组件（带缓存）
struct VideoThumbnailView: View {
    let assetId: String
    let size: CGSize
    
    @State private var thumbnail: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            if let image = thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: size.width, height: size.height)
                    .overlay(
                        Group {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "video.slash")
                                    .foregroundColor(.gray)
                            }
                        }
                    )
            }
        }
        .task {
            await loadThumbnail()
        }
    }
    
    private func loadThumbnail() async {
        guard let asset = PhotoLibraryService.shared.fetchAsset(withIdentifier: assetId) else {
            isLoading = false
            return
        }
        let pixelSize = CGSize(width: size.width * 2, height: size.height * 2)
        thumbnail = await PhotoLibraryService.shared.fetchThumbnail(for: asset, size: pixelSize)
        isLoading = false
    }
}

// 视频时长格式化
func formatDuration(_ duration: TimeInterval) -> String {
    let totalSeconds = Int(duration)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
}

// 分析状态徽章
struct AnalysisStatusBadge: View {
    let status: AnalysisStatus
    
    var body: some View {
        Text(status.rawValue)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15))
            .foregroundColor(badgeColor)
            .clipShape(Capsule())
    }
    
    private var badgeColor: Color {
        switch status {
        case .notAnalyzed: return .gray
        case .analyzing: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }
}
