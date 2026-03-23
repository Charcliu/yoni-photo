
//
//  VideoDetailView.swift
//  YoniPhoto
//
//  Created by 刘畅 on 2026/3/21.
//

import SwiftUI
import Photos
import AVKit
import AVFoundation
import CoreLocation
import MapKit

// 视频原始元数据
struct VideoRawMetadata {
    var locationName: String?       // 反地理编码地名
    var coordinate: CLLocationCoordinate2D?
    var cameraMake: String?         // 相机品牌
    var cameraModel: String?        // 相机型号
    var lensModel: String?          // 镜头型号
    var focalLength: String?        // 焦距
    var aperture: String?           // 光圈
    var iso: String?                // ISO
}

struct VideoDetailView: View {
    let video: VideoItem
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isLoadingPlayer = true
    @State private var rawMetadata: VideoRawMetadata?
    @State private var isLoadingMetadata = true
    @State private var photoImage: UIImage?   // 图片预览
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 媒体预览区域
                ZStack {
                    Color.black
                        .frame(height: 240)
                    
                    if video.mediaType == .photo {
                        // 图片预览
                        if let image = photoImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 240)
                        } else if isLoadingPlayer {
                            ProgressView()
                                .tint(.white)
                                .frame(height: 240)
                        }
                    } else {
                        // 视频播放器
                        if let player = player {
                            VideoPlayer(player: player)
                                .frame(height: 240)
                        } else if isLoadingPlayer {
                            ProgressView()
                                .tint(.white)
                                .frame(height: 240)
                        }
                    }
                }
                .frame(height: 240)
                .onAppear {
                    if video.mediaType == .photo {
                        loadPhoto()
                    } else {
                        loadPlayer()
                    }
                    loadMetadata()
                }
                .onDisappear {
                    player?.pause()
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
                        
                        Divider()
                        
                        // 原始信息
                        rawInfoSection
                        
                    } else {
                    // 未分析状态
                        VStack(spacing: 12) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text(video.mediaType == .photo ? "该图片尚未分析" : "该视频尚未分析")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("返回图库，选中该媒体后点击「分析」")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        
                        Divider()
                        
                        // 原始信息（未分析时也显示）
                        rawInfoSection
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(video.mediaType == .photo ? "图片详情" : "视频详情")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - 加载图片
    
    private func loadPhoto() {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [video.id], options: nil)
        guard let asset = fetchResult.firstObject else {
            isLoadingPlayer = false
            return
        }
        
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 1024, height: 1024),
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                self.photoImage = image
                self.isLoadingPlayer = false
            }
        }
    }
    
    // MARK: - 私有方法
    
    private func loadPlayer() {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [video.id], options: nil)
        guard let asset = fetchResult.firstObject else {
            isLoadingPlayer = false
            return
        }
        
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
            DispatchQueue.main.async {
                if let playerItem = playerItem {
                    self.player = AVPlayer(playerItem: playerItem)
                }
                self.isLoadingPlayer = false
            }
        }
    }
    
    // MARK: - 原始信息视图
    
    @ViewBuilder
    private var rawInfoSection: some View {
        InfoSection(title: "原始信息", icon: "camera") {
            if isLoadingMetadata {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("读取元数据...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 10) {
                    // 拍摄时间
                    if let date = video.creationDate {
                        DetailRow(
                            label: "拍摄时间",
                            value: formatCreationDate(date),
                            icon: "calendar"
                        )
                    }
                    
                    // 视频时长（仅视频显示）
                    if video.mediaType == .video {
                        DetailRow(
                            label: "时长",
                            value: formatDuration(video.duration),
                            icon: "clock"
                        )
                    }
                    
                    // 拍摄地点
                    if let locationName = rawMetadata?.locationName {
                        DetailRow(label: "拍摄地点", value: locationName, icon: "location")
                    }
                    
                    // 相机品牌/型号
                    if let make = rawMetadata?.cameraMake, let model = rawMetadata?.cameraModel {
                        let device = make == model || model.hasPrefix(make) ? model : "\(make) \(model)"
                        DetailRow(label: "拍摄设备", value: device, icon: "iphone")
                    } else if let model = rawMetadata?.cameraModel {
                        DetailRow(label: "拍摄设备", value: model, icon: "iphone")
                    }
                    
                    // 镜头型号
                    if let lens = rawMetadata?.lensModel {
                        DetailRow(label: "镜头", value: lens, icon: "camera.aperture")
                    }
                    
                    // 焦距
                    if let focal = rawMetadata?.focalLength {
                        DetailRow(label: "焦距", value: focal, icon: "scope")
                    }
                    
                    // 光圈
                    if let aperture = rawMetadata?.aperture {
                        DetailRow(label: "光圈", value: aperture, icon: "camera.filters")
                    }
                    
                    // ISO
                    if let iso = rawMetadata?.iso {
                        DetailRow(label: "ISO", value: iso, icon: "sun.max")
                    }
                    
                    // 文件名
                    DetailRow(label: "文件名", value: video.filename, icon: "doc")
                }
            }
        }
    }
    
    // MARK: - 加载元数据
    
    private func loadMetadata() {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [video.id], options: nil)
        guard let asset = fetchResult.firstObject else {
            isLoadingMetadata = false
            return
        }
        
        var metadata = VideoRawMetadata()
        
        // 读取地理位置
        if let location = asset.location {
            metadata.coordinate = location.coordinate
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(location) { placemarks, _ in
                DispatchQueue.main.async {
                    if let placemark = placemarks?.first {
                        var parts: [String] = []
                        if let country = placemark.country { parts.append(country) }
                        if let adminArea = placemark.administrativeArea { parts.append(adminArea) }
                        if let locality = placemark.locality { parts.append(locality) }
                        if let subLocality = placemark.subLocality { parts.append(subLocality) }
                        metadata.locationName = parts.isEmpty ? nil : parts.joined(separator: " · ")
                    }
                    self.rawMetadata = metadata
                    self.isLoadingMetadata = false
                }
            }
        } else {
            // 无位置信息
            if video.mediaType == .video {
                // 视频：读取 AVAsset metadata
                loadAVMetadata(asset: asset, metadata: metadata)
            } else {
                // 图片：直接完成
                rawMetadata = metadata
                isLoadingMetadata = false
            }
        }
    }
    
    private func loadAVMetadata(asset: PHAsset, metadata: VideoRawMetadata) {
        var meta = metadata
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .fastFormat
        
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            guard let avAsset = avAsset else {
                DispatchQueue.main.async {
                    self.rawMetadata = meta
                    self.isLoadingMetadata = false
                }
                return
            }
            
            // 读取所有 metadata
            let allMetadata = avAsset.metadata
            
            for item in allMetadata {
                guard let key = item.commonKey?.rawValue else { continue }
                switch key {
                case AVMetadataKey.commonKeyMake.rawValue:
                    meta.cameraMake = item.stringValue
                case AVMetadataKey.commonKeyModel.rawValue:
                    meta.cameraModel = item.stringValue
                case AVMetadataKey.commonKeySoftware.rawValue:
                    break
                default:
                    break
                }
            }
            
            // 尝试读取 iOS 格式的 metadata（QuickTime）
            let qtMetadata = AVMetadataItem.metadataItems(from: allMetadata, filteredByIdentifier: .quickTimeMetadataModel)
            if let modelItem = qtMetadata.first, meta.cameraModel == nil {
                meta.cameraModel = modelItem.stringValue
            }
            
            let makeItems = AVMetadataItem.metadataItems(from: allMetadata, filteredByIdentifier: .quickTimeMetadataMake)
            if let makeItem = makeItems.first, meta.cameraMake == nil {
                meta.cameraMake = makeItem.stringValue
            }
            
            // 读取 EXIF 数据（部分视频格式支持）
            for format in avAsset.availableMetadataFormats {
                let formatMetadata = avAsset.metadata(forFormat: format)
                for item in formatMetadata {
                    if let identifier = item.identifier?.rawValue {
                        if identifier.contains("lens") || identifier.contains("Lens") {
                            if let val = item.stringValue, !val.isEmpty {
                                meta.lensModel = val
                            }
                        }
                        if identifier.contains("FocalLength") || identifier.contains("focalLength") {
                            if let val = item.numberValue {
                                meta.focalLength = "\(val)mm"
                            }
                        }
                        if identifier.contains("FNumber") || identifier.contains("aperture") {
                            if let val = item.numberValue {
                                meta.aperture = "f/\(val)"
                            }
                        }
                        if identifier.contains("ISO") || identifier.contains("iso") {
                            if let val = item.numberValue {
                                meta.iso = "\(val)"
                            }
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.rawMetadata = meta
                self.isLoadingMetadata = false
            }
        }
    }
    
    // MARK: - 格式化工具
    
    private func formatCreationDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月dd日 HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
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
                .padding(.top, 2)
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 56, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.subheadline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
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

