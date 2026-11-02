import SwiftUI
import Photos

struct DeletionReviewView: View {
    @ObservedObject var vm: SwipeDeckViewModel
    let review: DeletionReview
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String>
    @State private var preview: PhotoPreview?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    init(vm: SwipeDeckViewModel, review: DeletionReview) {
        self.vm = vm
        self.review = review
        _selected = State(initialValue: Set(review.assets.map(\.localIdentifier)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tap a photo to inspect it. Uncheck any photo you want to keep. Nothing is deleted until you confirm below and approve Apple's dialog.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(review.assets, id: \.localIdentifier) { asset in
                            cell(asset)
                        }
                    }
                }.padding(16)
            }
            .navigationTitle("Review \(selected.count) photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(vm.isCommitting)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(role: .destructive) {
                    Task { _ = await vm.confirmDeletion(review, selected: selected) }
                } label: {
                    HStack {
                        if vm.isCommitting { ProgressView() }
                        Label(selected.isEmpty ? "No photos selected" : "Delete \(selected.count) photos", systemImage: "trash")
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent).tint(Theme.trash)
                .disabled(selected.isEmpty || vm.isCommitting)
                .padding().background(.ultraThinMaterial)
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(vm.isCommitting)
        .fullScreenCover(item: $preview) { request in
            PhotoPreviewView(preview: request,
                isSelected: { selected.contains($0) }, toggleSelection: { toggle($0) })
        }
        .alert("Deletion not completed", isPresented: Binding(
            get: { vm.operationError != nil }, set: { if !$0 { vm.operationError = nil } }
        )) {
            Button("OK", role: .cancel) { vm.operationError = nil }
        } message: { Text(vm.operationError ?? "Please try again.") }
    }

    private func cell(_ asset: PHAsset) -> some View {
        let id = asset.localIdentifier
        return Button {
            preview = PhotoPreview(assets: review.assets, initialID: id)
        } label: {
            GeometryReader { geometry in
                Thumbnail(asset: asset, side: geometry.size.width)
                    .opacity(selected.contains(id) ? 1 : 0.4)
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Preview photo \(asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "")")
        .overlay(alignment: .topTrailing) {
            Button { toggle(id) } label: {
                Image(systemName: selected.contains(id) ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(.white, selected.contains(id) ? Theme.trash : .black)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(selected.contains(id) ? "Keep this photo" : "Select this photo for deletion")
        }
        .disabled(vm.isCommitting)
    }

    private func toggle(_ id: String) {
        guard !vm.isCommitting else { return }
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        vm.setReviewSelection(selected, review: review)
    }
}
