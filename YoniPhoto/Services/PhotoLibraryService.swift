
//
//  PhotoLibraryService.swift
//  YoniPhoto
//
//  Created by 刘畅 on 2026/3/21.
//

import Foundation
import Photos
import UIKit
import Combine

class PhotoLibraryService: NSObject, ObservableObject {
    static let shared = PhotoLibraryService()
    
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    
    private override init() {
        super.init()
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
    
    // MARK: - 权限请求
    
    func requestAuthorization() async -> PHAuthorizationStatus {
        // 必须用 completion handler 版本，async 版本在 @MainActor 上无法弹出系统授权弹窗
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
                DispatchQueue.main.async {
                    self?.authorizationStatus = status
                    continuation.resume(returning: status)
                }
            }
        }
    }
    
    // MARK: - 获取媒体列表
    
    func fetchAllVideos() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        
        let result = PHAsset.fetchAssets(with: .video, options: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }
    
    /// 获取所有媒体（图片 + 视频），按拍摄时间倒序
    func fetchAllMedia() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }
    
    func fetchAsset(withIdentifier identifier: String) -> PHAsset? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        return result.firstObject
    }
    
    // MARK: - 获取视频缩略图
    
    func fetchThumbnail(for asset: PHAsset, size: CGSize = CGSize(width: 200, height: 200)) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast
            options.isSynchronous = false
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
    
    // MARK: - 获取视频URL（用于分析）
    
    func fetchVideoURL(for asset: PHAsset) async -> URL? {
        return await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                if let urlAsset = avAsset as? AVURLAsset {
                    continuation.resume(returning: urlAsset.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    // MARK: - 图片帧提取（用于AI分析）
    
    /// 提取图片资源的图像（直接返回原图，用于AI分析）
    func extractPhotoImage(from asset: PHAsset) async -> [UIImage] {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .exact
            options.isSynchronous = false
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 1024, height: 1024),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                if let image = image {
                    continuation.resume(returning: [image])
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    // MARK: - 视频帧提取（用于AI分析）
    
    func extractFrames(from asset: PHAsset, count: Int = 3) async -> [UIImage] {
        return await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard let avAsset = avAsset else {
                    continuation.resume(returning: [])
                    return
                }
                
                let generator = AVAssetImageGenerator(asset: avAsset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 512, height: 512)
                
                let duration = avAsset.duration.seconds
                var times: [NSValue] = []
                
                // 均匀分布取帧：开头、中间、结尾
                let intervals = max(1, count)
                for i in 0..<intervals {
                    let t = duration * Double(i) / Double(intervals) + duration / Double(intervals * 2)
                    let cmTime = CMTime(seconds: min(t, duration - 0.1), preferredTimescale: 600)
                    times.append(NSValue(time: cmTime))
                }
                
                var images: [UIImage] = []
                let group = DispatchGroup()
                
                for time in times {
                    group.enter()
                    generator.generateCGImagesAsynchronously(forTimes: [time]) { _, cgImage, _, _, _ in
                        if let cgImage = cgImage {
                            images.append(UIImage(cgImage: cgImage))
                        }
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) {
                    continuation.resume(returning: images)
                }
            }
        }
    }
    
    // MARK: - 创建相册
    
    func createAlbum(named name: String) async throws -> PHAssetCollection? {
        var albumPlaceholder: PHObjectPlaceholder?
        
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            albumPlaceholder = request.placeholderForCreatedAssetCollection
        }
        
        guard let placeholder = albumPlaceholder else { return nil }
        let collections = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [placeholder.localIdentifier],
            options: nil
        )
        return collections.firstObject
    }
    
    func findAlbum(named name: String) -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title == %@", name)
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options)
        return collections.firstObject
    }
    
    // MARK: - 添加视频到相册
    
    func addAssets(_ assetIds: [String], toAlbum albumName: String) async throws {
        // 查找或创建相册
        var album = findAlbum(named: albumName)
        if album == nil {
            album = try await createAlbum(named: albumName)
        }
        guard let targetAlbum = album else {
            throw PhotoLibraryError.albumCreationFailed
        }
        
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: nil)
        
        try await PHPhotoLibrary.shared().performChanges {
            guard let albumRequest = PHAssetCollectionChangeRequest(for: targetAlbum) else { return }
            albumRequest.addAssets(assets)
        }
    }
    
    // MARK: - 获取所有自定义相册
    
    func fetchUserAlbums() -> [PHAssetCollection] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "localizedTitle", ascending: true)]
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options)
        var albums: [PHAssetCollection] = []
        result.enumerateObjects { collection, _, _ in
            albums.append(collection)
        }
        return albums
    }
}

// MARK: - 错误类型

enum PhotoLibraryError: LocalizedError {
    case authorizationDenied
    case albumCreationFailed
    case assetNotFound
    
    var errorDescription: String? {
        switch self {
        case .authorizationDenied: return "相册访问权限被拒绝"
        case .albumCreationFailed: return "创建相册失败"
        case .assetNotFound: return "找不到视频资源"
        }
    }
}
