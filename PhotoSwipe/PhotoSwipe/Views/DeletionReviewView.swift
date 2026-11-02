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
        VStack(spacing: 0) {
            HStack {
                PhotoChromeButton(symbol: "xmark", label: "Close") { dismiss() }
                    .accessibilityIdentifier("review-close")
                    .disabled(vm.isCommitting)
                Spacer()
                VStack(spacing: 1) {
                    Text("REVIEW")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1.6).foregroundStyle(Theme.textDim)
                    Text("\(selected.count) photo\(selected.count == 1 ? "" : "s")")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(review.assets, id: \.localIdentifier) { asset in
                        cell(asset)
                    }
                }.padding(.horizontal, 20).padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
            PhotoPrimaryButton(title: selected.isEmpty ? "Nothing selected" : "Delete \(selected.count)",
                               symbol: "trash.fill", busy: vm.isCommitting, enabled: !selected.isEmpty) {
                Task { _ = await vm.confirmDeletion(review, selected: selected) }
            }
            .accessibilityIdentifier("confirm-deletion")
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 18)
        }
        .background(AuroraBackground())
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
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.stroke))
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("review-photo")
        .accessibilityLabel("Preview photo \(asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "")")
        .overlay(alignment: .topTrailing) {
            Button { toggle(id) } label: {
                Image(systemName: selected.contains(id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white, selected.contains(id) ? Theme.trash : Theme.card)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("review-toggle")
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
