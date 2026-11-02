import SwiftUI
import Photos

/// Review duplicate groups. Each group shows its photos; tap to toggle a photo
/// between keep (green ring) and trash (dimmed + red ring). Keeper is suggested
/// automatically (highest resolution).
struct DuplicatesView: View {
    @ObservedObject var vm: SwipeDeckViewModel
    @State private var preview: PhotoPreview?

    var body: some View {
        Group {
            if vm.duplicateGroups.isEmpty {
                emptyState
            } else {
                groupsList
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !vm.duplicateGroups.isEmpty { commitBar }
        }
        .fullScreenCover(item: $preview) { request in
            PhotoPreviewView(preview: request,
                isSelected: { id in vm.duplicateGroups.contains { $0.trashIDs.contains(id) } },
                toggleSelection: { id in
                    if let group = vm.duplicateGroups.first(where: { $0.assets.contains { $0.localIdentifier == id } }) {
                        vm.toggleTrash(group: group.id, asset: id)
                    }
                })
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            backButton
            Spacer()
            VStack(spacing: 1) {
                Text("DUPLICATES")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(1.6).foregroundStyle(Theme.textDim)
                Text("\(vm.duplicateGroups.count) group\(vm.duplicateGroups.count == 1 ? "" : "s")")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
            }
            Spacer()
            PhotoChromeButton(symbol: "arrow.clockwise", label: "Scan for more") { vm.scanForMore() }
                .accessibilityValue("\(vm.unscannedPhotoCount) unscanned photos")
                .accessibilityIdentifier("scan-more")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var backButton: some View {
        Button { Haptics.tap(); vm.backToPicker() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Theme.stroke))
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("duplicates-back")
    }

    // MARK: Groups

    private var groupsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if vm.scanUnavailable > 0 {
                    Label("\(vm.scanUnavailable) unavailable", systemImage: "icloud.slash")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textDim)
                }
                ForEach(vm.duplicateGroups) { group in
                    groupCard(group)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func groupCard(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(group.assets.count) similar")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(group.trashIDs.count) to delete")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(group.trashIDs.isEmpty ? Theme.textDim : Theme.trash)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(group.assets, id: \.localIdentifier) { asset in
                        cell(asset, in: group)
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke))
    }

    private func cell(_ asset: PHAsset, in group: DuplicateGroup) -> some View {
        let trashed = group.trashIDs.contains(asset.localIdentifier)
        let isKeeper = group.keeperID == asset.localIdentifier
        return Thumbnail(asset: asset, side: 96)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(trashed ? Theme.trash : Theme.keep, lineWidth: 3)
                )
                .overlay(alignment: .topTrailing) {
                    Image(systemName: trashed ? "trash.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white, trashed ? Theme.trash : Theme.keep)
                        .padding(5)
                }
                .overlay(alignment: .bottomLeading) {
                    if isKeeper {
                        Text("BEST")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Theme.favorite, in: Capsule())
                            .padding(5)
                    }
                }
                .opacity(trashed ? 0.55 : 1)
                .animation(.snappy(duration: 0.2), value: trashed)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .gesture(LongPressGesture(minimumDuration: 0.35).exclusively(before: TapGesture())
            .onEnded { result in
                switch result {
                case .first:
                    preview = PhotoPreview(assets: group.assets, initialID: asset.localIdentifier)
                case .second:
                    vm.toggleTrash(group: group.id, asset: asset.localIdentifier)
                }
            })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trashed ? "Photo selected for deletion" : "Photo kept")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("duplicate-photo")
        .accessibilityAction { vm.toggleTrash(group: group.id, asset: asset.localIdentifier) }
        .accessibilityAction(named: "Preview and compare") {
            preview = PhotoPreview(assets: group.assets, initialID: asset.localIdentifier)
        }
    }

    // MARK: Commit

    private var commitBar: some View {
        PhotoPrimaryButton(title: vm.duplicateTrashCount == 0 ? "Nothing selected" : "Review \(vm.duplicateTrashCount)",
                           symbol: "trash.fill", busy: vm.isCommitting, enabled: vm.duplicateTrashCount > 0) {
            Task { await vm.commitDuplicates() }
        }
        .accessibilityIdentifier("review-duplicates")
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.gradient(Theme.keep, Theme.keep2))
            Text("No matches")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            if vm.scanUnavailable > 0 {
                Label("\(vm.scanUnavailable) unavailable", systemImage: "icloud.slash")
                    .font(.system(.subheadline, design: .rounded)).foregroundStyle(Theme.textDim)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
