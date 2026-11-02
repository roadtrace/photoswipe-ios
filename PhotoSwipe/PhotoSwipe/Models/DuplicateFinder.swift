import Photos
import CoreGraphics
import UIKit

struct DuplicateGroup: Identifiable {
    let id = UUID()
    var assets: [PHAsset]
    var keeperID: String
    // Similarity is not proof: users explicitly select every deletion.
    var trashIDs: Set<String> = []

    init(assets: [PHAsset]) {
        self.assets = assets
        let keeper = assets.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            let left = $0.pixelWidth * $0.pixelHeight
            let right = $1.pixelWidth * $1.pixelHeight
            if left != right { return left > right }
            return $0.localIdentifier < $1.localIdentifier
        }.first
        keeperID = keeper?.localIdentifier ?? ""
    }
}

final class DuplicateFinder {
    private let service: PhotoLibraryService
    init(service: PhotoLibraryService) { self.service = service }

    func scan(_ input: [PHAsset], cached: [String: CachedPhotoSignature],
              progress: @MainActor @escaping (Double, Int) -> Void) async -> DuplicateScanSnapshot {
        let assets = input.sorted { $0.localIdentifier < $1.localIdentifier }
        var matcher = DuplicateMatcher()
        var unavailable = 0
        var signatures: [String: CachedPhotoSignature] = [:]
        for (index, asset) in assets.enumerated() {
            let revision = Self.revision(asset)
            if let saved = cached[asset.localIdentifier], saved.revision == revision {
                signatures[asset.localIdentifier] = saved
                matcher.insert(saved.signature, index: index)
            } else if let image = await service.requestImage(for: asset,
                    targetSize: CGSize(width: 256, height: 256), contentMode: .aspectFit),
               let signature = Self.signature(image) {
                signatures[asset.localIdentifier] = CachedPhotoSignature(revision: revision, signature: signature)
                matcher.insert(signature, index: index)
            } else {
                unavailable += 1
            }
            await progress(Double(index + 1) / Double(assets.count), unavailable)
        }
        await progress(1, unavailable)
        let groups = matcher.groups.filter { $0.count > 1 }
            .map { DuplicateGroup(assets: $0.map { assets[$0] }) }
            .sorted {
                if $0.assets.count != $1.assets.count { return $0.assets.count > $1.assets.count }
                return $0.keeperID < $1.keeperID
            }
        return DuplicateScanSnapshot(signatures: signatures, groups: groups.map {
            SavedDuplicateGroup(assetIDs: $0.assets.map(\.localIdentifier),
                                keeperID: $0.keeperID, trashIDs: [])
        }, scannedAt: Date(), unavailable: unavailable)
    }

    static func revision(_ asset: PHAsset) -> PhotoRevision {
        PhotoRevision(modified: asset.modificationDate, width: asset.pixelWidth, height: asset.pixelHeight)
    }

    private static func signature(_ image: UIImage) -> DuplicateSignature? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        // UIImage rendering normalizes EXIF orientation before comparison.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format)
        guard let cg = renderer.image(actions: {
            $0.cgContext.setFillColor(UIColor.black.cgColor)
            $0.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            image.draw(in: CGRect(x: 0, y: 0, width: 64, height: 64))
        }).cgImage,
        let horizontal = hash(cg, width: 9, height: 8, vertical: false),
        let vertical = hash(cg, width: 8, height: 9, vertical: true),
        let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
            bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 4, height: 4))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: 64)
        let colors = (0..<16).flatMap { cell in (0..<3).map { pixels[cell * 4 + $0] } }
        return DuplicateSignature(horizontal: horizontal, vertical: vertical,
            colors: colors, aspect: Double(image.size.width / image.size.height))
    }

    private static func hash(_ cg: CGImage, width: Int, height: Int, vertical: Bool) -> UInt64? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)
        var result: UInt64 = 0
        for row in 0..<8 {
            for column in 0..<8 {
                let a = row * width + column
                let b = a + (vertical ? width : 1)
                if pixels[a] < pixels[b] { result |= UInt64(1) << (row * 8 + column) }
            }
        }
        return result
    }
}
