import SwiftUI
import Photos
import UIKit

/// Shared preview for comparison and deletion review. Selection is always explicit.
struct PhotoPreviewView: View {
    let preview: PhotoPreview
    var isSelected: ((String) -> Bool)? = nil
    var toggleSelection: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String
    @State private var selectedForDeletion: Set<String>

    init(preview: PhotoPreview, isSelected: ((String) -> Bool)? = nil,
         toggleSelection: ((String) -> Void)? = nil) {
        self.preview = preview
        self.isSelected = isSelected
        self.toggleSelection = toggleSelection
        _selectedID = State(initialValue: preview.initialID)
        _selectedForDeletion = State(initialValue: Set(preview.assets.map(\.localIdentifier).filter { isSelected?($0) == true }))
    }

    private var index: Int { preview.assets.firstIndex { $0.localIdentifier == selectedID } ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                PhotoChromeButton(symbol: "xmark", label: "Done") { dismiss() }
                    .accessibilityIdentifier("preview-close")
                Spacer()
                VStack(spacing: 1) {
                    Text("PHOTO")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1.6).foregroundStyle(Theme.textDim)
                    Text("\(index + 1) / \(preview.assets.count)")
                        .font(.system(.headline, design: .rounded).weight(.bold)).monospacedDigit()
                }
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            TabView(selection: $selectedID) {
                ForEach(preview.assets, id: \.localIdentifier) { asset in
                    PreviewPhotoPage(asset: asset, active: asset.localIdentifier == selectedID)
                        .tag(asset.localIdentifier)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            VStack(spacing: 12) {
                if let asset = preview.assets.first(where: { $0.localIdentifier == selectedID }) {
                    HStack(spacing: 10) {
                        if let date = asset.creationDate { Text(date.formatted(date: .abbreviated, time: .omitted)) }
                        Text("\(asset.pixelWidth) × \(asset.pixelHeight)")
                    }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textDim)
                }
                HStack(spacing: 36) {
                    PhotoChromeButton(symbol: "chevron.left", label: "Previous photo") { move(-1) }
                        .disabled(index == 0).opacity(index == 0 ? 0.3 : 1)
                    if let isSelected, let toggleSelection {
                        PhotoChromeButton(symbol: selectedForDeletion.contains(selectedID) ? "trash.fill" : "checkmark",
                            label: selectedForDeletion.contains(selectedID) ? "Keep photo" : "Select for deletion",
                            tint: selectedForDeletion.contains(selectedID) ? Theme.trash : Theme.keep, size: 56) {
                            toggleSelection(selectedID)
                            if isSelected(selectedID) { selectedForDeletion.insert(selectedID) }
                            else { selectedForDeletion.remove(selectedID) }
                        }
                        .accessibilityIdentifier("preview-selection")
                    }
                    PhotoChromeButton(symbol: "chevron.right", label: "Next photo") { move(1) }
                        .disabled(index == preview.assets.count - 1)
                        .opacity(index == preview.assets.count - 1 ? 0.3 : 1)
                }
            }
            .padding(.top, 12).padding(.bottom, 16)
        }
        .background(.black).foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

    private func move(_ delta: Int) {
        let next = index + delta
        guard preview.assets.indices.contains(next) else { return }
        selectedID = preview.assets[next].localIdentifier
    }
}

private struct PreviewPhotoPage: View {
    let asset: PHAsset
    let active: Bool
    @State private var image: UIImage?
    @State private var failed = false
    private let service = PhotoLibraryService()

    var body: some View {
        ZStack {
            Color.black
            if let image { ZoomablePhoto(image: image) }
            else if failed {
                VStack(spacing: 16) {
                    Image(systemName: "photo").font(.system(size: 44))
                        .foregroundStyle(Theme.gradient(Theme.album, Theme.keep))
                    Text("Photo unavailable")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                    Button("Try again") { Task { await load() } }
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .tint(Theme.album)
                }
            } else { ProgressView().tint(.white) }
        }
        .task(id: active) {
            if active { await load() }
            else { image = nil; failed = false }
        }
    }

    private func load() async {
        guard active else { return }
        failed = false
        // Bound decoding memory while retaining enough detail for zooming.
        let loaded = await service.requestImage(for: asset,
            targetSize: CGSize(width: 3072, height: 3072), contentMode: .aspectFit, highQuality: true)
        guard !Task.isCancelled, active else { return }
        image = loaded
        failed = loaded == nil
    }
}

private struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage
    func makeUIView(context: Context) -> PhotoZoomScrollView { PhotoZoomScrollView() }
    func updateUIView(_ view: PhotoZoomScrollView, context: Context) {
        if view.photo.image !== image {
            view.setZoomScale(1, animated: false)
            view.photo.image = image
        }
    }
}

private final class PhotoZoomScrollView: UIScrollView, UIScrollViewDelegate {
    let photo = UIImageView()
    private var viewport = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        accessibilityIdentifier = "zoom-photo"
        minimumZoomScale = 1
        maximumZoomScale = 6
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        photo.contentMode = .scaleAspectFit
        addSubview(photo)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if viewport != bounds.size {
            viewport = bounds.size
            setZoomScale(1, animated: false)
            photo.frame = CGRect(origin: .zero, size: viewport)
            contentSize = viewport
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { photo }

    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1 { setZoomScale(1, animated: true) }
        else {
            let point = gesture.location(in: photo)
            let size = CGSize(width: bounds.width / 3, height: bounds.height / 3)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height), animated: true)
        }
    }
}
