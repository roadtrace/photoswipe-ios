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
        VStack(spacing: 10) {
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
            Color.clear.frame(width: 44, height: 44)
        }
          HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let date = vm.duplicateScanDate {
                    Text("Saved \(date.formatted(date: .abbreviated, time: .shortened))")
                }
                if vm.unscannedPhotoCount > 0 { Text("\(vm.unscannedPhotoCount) new, changed, or unavailable photos") }
            }
            .font(.caption).foregroundStyle(Theme.textDim)
            Spacer()
            Button("Scan for more") { vm.scanForMore() }
                .font(.subheadline.weight(.semibold)).tint(Theme.album)
          }
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
                Text("Tap to select for deletion. Hold a photo to preview and compare. Similar photos may be different shots.")
                    .font(.footnote).foregroundStyle(Theme.textDim)
                if vm.scanUnavailable > 0 {
                    Text("\(vm.scanUnavailable) photos couldn't be loaded and were skipped.")
                        .font(.footnote).foregroundStyle(Theme.favorite)
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
                Text("\(group.assets.count) visually similar")
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
                        Text("SUGGESTED KEEP")
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
        Button { Task { await vm.commitDuplicates() } } label: {
            HStack(spacing: 10) {
                if vm.isCommitting { ProgressView().tint(.white) }
                else { Image(systemName: "trash.fill") }
                Text(vm.duplicateTrashCount == 0 ? "Nothing selected"
                     : "Review \(vm.duplicateTrashCount) photos")
                    .font(.system(.headline, design: .rounded).weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Theme.gradient(Theme.trash, Theme.trash2),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(.white)
            .shadow(color: Theme.trash.opacity(0.4), radius: 16, y: 8)
            .opacity(vm.duplicateTrashCount == 0 ? 0.45 : 1)
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .disabled(vm.duplicateTrashCount == 0 || vm.isCommitting)
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
            Text("No duplicates found")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(vm.scanUnavailable > 0
                 ? "\(vm.scanUnavailable) photos couldn't be loaded. Try again when iCloud photos are available."
                 : "No close visual matches found. Crops, edits, or low-detail images may not match.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textDim)
            Button("Back to filters") { Haptics.tap(); vm.backToPicker() }
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22).padding(.vertical, 13)
                .background(Theme.gradient(Theme.album, Theme.album2), in: Capsule())
                .buttonStyle(PressableStyle())
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
