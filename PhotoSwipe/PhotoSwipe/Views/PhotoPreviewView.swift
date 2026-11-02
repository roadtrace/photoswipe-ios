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
                Button("Done") { dismiss() }
                Spacer()
                Text("\(index + 1) of \(preview.assets.count)").monospacedDigit()
            }
            .padding()
            TabView(selection: $selectedID) {
                ForEach(preview.assets, id: \.localIdentifier) { asset in
                    PreviewPhotoPage(asset: asset, active: asset.localIdentifier == selectedID)
                        .tag(asset.localIdentifier)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            HStack {
                Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .disabled(index == 0).accessibilityLabel("Previous photo")
                Spacer()
                if let asset = preview.assets.first(where: { $0.localIdentifier == selectedID }) {
                    VStack(spacing: 3) {
                        if let date = asset.creationDate { Text(date.formatted(date: .abbreviated, time: .shortened)) }
                        Text("\(asset.pixelWidth) × \(asset.pixelHeight)")
                    }.font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .disabled(index == preview.assets.count - 1).accessibilityLabel("Next photo")
            }.padding(.horizontal)
            if let isSelected, let toggleSelection {
                Button {
                    toggleSelection(selectedID)
                    if isSelected(selectedID) { selectedForDeletion.insert(selectedID) }
                    else { selectedForDeletion.remove(selectedID) }
                } label: {
                    Label(selectedForDeletion.contains(selectedID) ? "Selected for deletion — tap to keep" : "Keep photo — tap to select for deletion",
                          systemImage: selectedForDeletion.contains(selectedID) ? "trash.circle.fill" : "checkmark.circle.fill")
                        .frame(maxWidth: .infinity).padding()
                }
                .tint(selectedForDeletion.contains(selectedID) ? Theme.trash : Theme.keep)
                .buttonStyle(.bordered)
                .padding(.horizontal)
            }
            Text("Pinch or double-tap to zoom. Swipe or use arrows to compare.")
                .font(.caption).foregroundStyle(.secondary).padding(.bottom, 10)
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
                ContentUnavailableView {
                    Label("Photo unavailable", systemImage: "photo")
                } description: {
                    Text("Check your connection for iCloud photos or your Photos access.")
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            } else { ProgressView("Loading photo…").tint(.white) }
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
