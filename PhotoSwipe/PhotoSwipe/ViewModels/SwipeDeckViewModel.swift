import SwiftUI
import Photos

@MainActor
final class SwipeDeckViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case permissionDenied
        case empty            // library has no photos at all
        case picker           // choose a source
        case scanning         // duplicate scan in progress
        case duplicates       // duplicate groups review
        case swiping
        case review
    }

    @Published var phase: Phase = .loading
    @Published private(set) var assets: [PHAsset] = []      // working deck
    @Published var index: Int = 0
    @Published private(set) var history: [SwipeAction] = []
    @Published var albums: [PHAssetCollection] = []
    @Published var isCommitting = false
    @Published private(set) var isApplyingDecision = false
    @Published var operationError: String?
    @Published var deletionReview: DeletionReview?
    var interactionLocked: Bool { isCommitting || isApplyingDecision }

    // Picker
    @Published private(set) var facets = LibraryFacets()
    @Published private(set) var source: PhotoSource = .all

    // Duplicates
    @Published private(set) var duplicateGroups: [DuplicateGroup] = []
    @Published var scanProgress: Double = 0
    @Published private(set) var scanUnavailable = 0
    @Published private(set) var duplicateScanDate: Date?
    @Published private(set) var unscannedPhotoCount = 0

    // Freed space
    @Published private(set) var estimatedFreeBytes: Int64 = 0
    @Published private(set) var freedBytes: Int64 = 0

    // Lifetime analytics
    @Published private(set) var stats = LifetimeStats()

    // Persisted trash queue (survives pause / quit)
    @Published private(set) var pendingTrashIDs: Set<String> = []

    private let service = PhotoLibraryService()
    private let store = ReviewStore()
    private let statsStore = StatsStore()
    private let trashStore = PendingTrashStore()
    private let scanStore = DuplicateScanStore()
    private var scanSnapshot: DuplicateScanSnapshot?
    private lazy var finder = DuplicateFinder(service: service)
    private var allImages: [PHAsset] = []

    // MARK: Derived

    /// Everything queued for deletion (this run + any leftover from a paused
    /// session), resolved against the current library.
    var pendingTrash: [PHAsset] {
        allImages.filter { pendingTrashIDs.contains($0.localIdentifier) }
    }
    var pendingTrashCount: Int { pendingTrashIDs.count }
    var keptCount: Int { history.filter { $0.decision == .keep }.count }
    var skippedCount: Int { history.filter { $0.decision == .skip }.count }
    var favoritedCount: Int { history.filter { if case .favorite = $0.decision { return true }; return false }.count }
    var albumedCount: Int { history.filter { if case .album = $0.decision { return true }; return false }.count }

    var current: PHAsset? { peek(0) }
    var next: PHAsset? { peek(1) }
    func peek(_ offset: Int) -> PHAsset? {
        let i = index + offset
        return assets.indices.contains(i) ? assets[i] : nil
    }
    var remaining: Int { max(assets.count - index, 0) }
    var progress: Double { assets.isEmpty ? 0 : Double(index) / Double(assets.count) }
    var canUndo: Bool { !history.isEmpty && !interactionLocked }

    var duplicateTrashCount: Int { duplicateGroups.reduce(0) { $0 + $1.trashIDs.count } }

    // MARK: Bootstrap

    func bootstrap() async {
        let status = service.authorizationStatus()
        switch status {
        case .authorized, .limited:
            await loadLibrary()
        case .notDetermined:
            let s = await service.requestAuthorization()
            if s == .authorized || s == .limited { await loadLibrary() }
            else { phase = .permissionDenied }
        default:
            phase = .permissionDenied
        }
    }

    private func loadLibrary() async {
        phase = .loading
        stats = statsStore.load()
        pendingTrashIDs = trashStore.ids
        allImages = service.fetchAllPhotos()
        scanSnapshot = scanStore.load()
        restoreDuplicateResults()
        albums = service.userAlbums()
        if allImages.isEmpty { phase = .empty; return }
        facets = computeFacets(allImages)
        phase = .picker
    }

    private func computeFacets(_ images: [PHAsset]) -> LibraryFacets {
        var f = LibraryFacets()
        f.total = images.count
        var yearCounts: [Int: Int] = [:]
        let cal = Calendar.current
        for a in images {
            if a.mediaSubtypes.contains(.photoScreenshot) { f.screenshots += 1 }
            if let d = a.creationDate { yearCounts[cal.component(.year, from: d), default: 0] += 1 }
        }
        f.years = yearCounts.map { (year: $0.key, count: $0.value) }.sorted { $0.year > $1.year }
        return f
    }

    // MARK: Source selection

    func select(_ source: PhotoSource) {
        self.source = source
        if source.isDuplicates {
            allImages = service.fetchAllPhotos()
            restoreDuplicateResults()
            if scanSnapshot != nil { phase = .duplicates }
            else { scanForMore() }
        } else {
            startDeck(for: source)
        }
    }

    private func startDeck(for source: PhotoSource) {
        service.stopCaching()
        history = []
        index = 0
        estimatedFreeBytes = 0
        freedBytes = 0

        var working = allImages.filter { !store.isReviewed($0.localIdentifier) }
        switch source {
        case .all: break
        case .screenshots:
            working = working.filter { $0.mediaSubtypes.contains(.photoScreenshot) }
        case .largest:
            working.sort { $0.pixelWidth * $0.pixelHeight > $1.pixelWidth * $1.pixelHeight }
        case .year(let y):
            let cal = Calendar.current
            working = working.filter {
                guard let d = $0.creationDate else { return false }
                return cal.component(.year, from: d) == y
            }
        case .duplicates: break
        }

        assets = working
        if working.isEmpty {
            phase = .review   // shows "nothing left here" state
        } else {
            phase = .swiping
            service.startCaching(Array(working.prefix(20)),
                                 targetSize: CGSize(width: 1080, height: 1080))
        }
    }

    func backToPicker() {
        service.stopCaching()
        facets = computeFacets(allImages)
        history = []
        phase = .picker
    }

    func resetProgress() {
        store.reset()
        backToPicker()
    }

    func resetStats() {
        statsStore.reset()
        stats = statsStore.load()
    }

    // MARK: Swipe decisions

    func decide(_ decision: Decision, expectedAssetID: String) async {
        guard phase == .swiping, !interactionLocked,
              let displayed = current, displayed.localIdentifier == expectedAssetID else { return }
        isApplyingDecision = true
        defer { isApplyingDecision = false }
        do {
            let asset = try service.currentAsset(expectedAssetID)
            let wasInAlbum: Bool
            if case .album(let id, _) = decision { wasInAlbum = service.contains(asset, albumID: id) }
            else { wasInAlbum = false }
            let action = SwipeAction(asset: asset, decision: decision,
                wasFavorite: asset.isFavorite, wasInAlbum: wasInAlbum,
                wasReviewed: store.isReviewed(expectedAssetID),
                wasPendingTrash: pendingTrashIDs.contains(expectedAssetID))
            if case .favorite = decision, !asset.isFavorite {
                try await service.setFavorite(asset, true)
            }
            if case .album(let id, _) = decision, !wasInAlbum {
                try await service.add(asset, toAlbumWithLocalIdentifier: id)
            }
            history.append(action)

            switch decision {
            case .favorite, .album, .keep:
                store.mark(asset.localIdentifier)
            case .trash:
                store.mark(asset.localIdentifier)
                trashStore.add(asset.localIdentifier)
                pendingTrashIDs.insert(asset.localIdentifier)
            case .skip:
                break // Reappears next session.
            }
            advance()
        } catch {
            operationError = "Couldn't apply this action. \(error.localizedDescription)"
            Haptics.warning()
        }
    }

    private func advance() {
        if index + 1 >= assets.count {
            index = assets.count
            Task { await computeFreeEstimate() }
            phase = .review
        } else {
            index += 1
        }
    }

    func undo() async {
        guard !interactionLocked, let last = history.last else { return }
        isApplyingDecision = true
        defer { isApplyingDecision = false }
        do {
            let asset = try service.currentAsset(last.asset.localIdentifier)
            guard let restoredIndex = assets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier })
            else { throw PhotoLibraryService.LibraryError.assetUnavailable }
            switch last.decision {
            case .favorite:
                if asset.isFavorite != last.wasFavorite {
                    try await service.setFavorite(asset, last.wasFavorite)
                }
            case .album(let id, _):
                if !last.wasInAlbum && service.contains(asset, albumID: id) {
                    try await service.remove(asset, fromAlbumWithLocalIdentifier: id)
                }
            default: break
            }
            // Only consume undo after the Photos mutation succeeds.
            history.removeLast()
            let id = asset.localIdentifier
            if last.wasReviewed { store.mark(id) } else { store.unmark(id) }
            if last.wasPendingTrash { trashStore.add(id); pendingTrashIDs.insert(id) }
            else { trashStore.remove(id); pendingTrashIDs.remove(id) }
            index = restoredIndex
            estimatedFreeBytes = 0
            phase = .swiping
            Haptics.tap(.medium)
        } catch {
            operationError = "Couldn't undo. Your undo history is still available. \(error.localizedDescription)"
            Haptics.warning()
        }
    }

    // MARK: Albums

    func createAlbum(named name: String) async -> (id: String, title: String)? {
        guard let id = try? await service.createAlbum(named: name) else { return nil }
        albums = service.userAlbums()
        return (id, name)
    }

    // MARK: Freed space

    private func computeFreeEstimate() async {
        let assetsToFree = pendingTrash
        let expectedIDs = pendingTrashIDs
        let bytes = await Task.detached { [service] in service.totalBytes(of: assetsToFree) }.value
        guard phase == .review, pendingTrashIDs == expectedIDs else { return }
        estimatedFreeBytes = bytes
    }

    // MARK: Deletion review

    func commitPendingTrash(returnToPicker: Bool) async {
        guard !interactionLocked else { return }
        guard !pendingTrash.isEmpty else {
            if returnToPicker { backToPicker() }
            return
        }
        deletionReview = DeletionReview(assets: pendingTrash, source: .pending(returnToPicker: returnToPicker))
    }

    func commitDeletions() async { await commitPendingTrash(returnToPicker: true) }

    func commitDuplicates() async {
        guard !interactionLocked else { return }
        let selected = Set(duplicateGroups.flatMap { $0.trashIDs })
        let photos = duplicateGroups.flatMap { $0.assets }.filter { selected.contains($0.localIdentifier) }
        guard !photos.isEmpty else { return }
        deletionReview = DeletionReview(assets: photos, source: .duplicates)
    }

    func setReviewSelection(_ selected: Set<String>, review: DeletionReview) {
        guard !interactionLocked else { return }
        let candidates = Set(review.assets.map(\.localIdentifier))
        let selected = selected.intersection(candidates)
        switch review.source {
        case .pending:
            for id in candidates {
                if selected.contains(id) { trashStore.add(id); pendingTrashIDs.insert(id) }
                else { trashStore.remove(id); pendingTrashIDs.remove(id) }
            }
        case .duplicates:
            for index in duplicateGroups.indices {
                duplicateGroups[index].trashIDs.subtract(candidates)
                duplicateGroups[index].trashIDs.formUnion(selected.intersection(
                    duplicateGroups[index].assets.map(\.localIdentifier)))
            }
            saveDuplicateResults()
        }
    }

    /// The only route to PhotoKit deletion: an explicit selection from the grid.
    func confirmDeletion(_ review: DeletionReview, selected: Set<String>) async -> Bool {
        guard !interactionLocked, deletionReview?.id == review.id, !selected.isEmpty,
              selected.isSubset(of: Set(review.assets.map(\.localIdentifier))) else { return false }
        isCommitting = true
        defer { isCommitting = false }
        let fresh = service.fetchAllPhotos()
        let available = Set(fresh.map(\.localIdentifier))
        var groups: [Set<String>] = []
        if case .duplicates = review.source {
            groups = duplicateGroups.map { Set($0.assets.map(\.localIdentifier)) }
        }
        guard DeletionSelection.isValid(selected, reviewed: Set(review.assets.map(\.localIdentifier)),
                                        available: available, duplicateGroups: groups) else {
            operationError = "Some reviewed photos or a group's keeper are no longer accessible. Close this review and check your selection again."
            return false
        }
        let toDelete = fresh.filter { selected.contains($0.localIdentifier) }
        let bytes = await Task.detached { [service] in service.totalBytes(of: toDelete) }.value
        do {
            try await service.deleteAssets(toDelete)
            var duplicates = 0
            if case .duplicates = review.source { duplicates = toDelete.count }
            stats = statsStore.record(freed: bytes, deleted: toDelete.count, duplicates: duplicates)
            freedBytes = bytes
            estimatedFreeBytes = 0
            for id in selected { trashStore.remove(id); pendingTrashIDs.remove(id) }
            history.removeAll { selected.contains($0.asset.localIdentifier) }
            let currentID = current?.localIdentifier
            assets.removeAll { selected.contains($0.localIdentifier) }
            index = currentID.flatMap { id in assets.firstIndex { $0.localIdentifier == id } } ?? assets.count
            allImages = service.fetchAllPhotos()
            restoreDuplicateResults()
            facets = computeFacets(allImages)
            deletionReview = nil
            if case .pending(let returnToPicker) = review.source, returnToPicker { backToPicker() }
            Haptics.success()
            return true
        } catch {
            operationError = "Deletion wasn't completed. Your remaining selections are saved. \(error.localizedDescription)"
            Haptics.warning()
            return false
        }
    }

    // MARK: Saved duplicates

    private func restoreDuplicateResults() {
        let revisions = Dictionary(uniqueKeysWithValues: allImages.map {
            ($0.localIdentifier, DuplicateFinder.revision($0))
        })
        if let snapshot = scanSnapshot {
            scanSnapshot = snapshot.reconciled(with: revisions)
        }
        let byID = Dictionary(uniqueKeysWithValues: allImages.map { ($0.localIdentifier, $0) })
        duplicateGroups = (scanSnapshot?.groups ?? []).compactMap { saved in
            let photos = saved.assetIDs.compactMap { byID[$0] }
            guard photos.count > 1 else { return nil }
            var group = DuplicateGroup(assets: photos)
            group.keeperID = saved.keeperID
            group.trashIDs = saved.trashIDs
            return group
        }
        duplicateScanDate = scanSnapshot?.scannedAt
        scanUnavailable = scanSnapshot?.unavailable ?? 0
        unscannedPhotoCount = revisions.filter { scanSnapshot?.signatures[$0.key]?.revision != $0.value }.count
        if scanSnapshot != nil { saveDuplicateResults() }
    }

    private func saveDuplicateResults() {
        guard var snapshot = scanSnapshot else { return }
        snapshot.groups = duplicateGroups.map {
            SavedDuplicateGroup(assetIDs: $0.assets.map(\.localIdentifier),
                                keeperID: $0.keeperID, trashIDs: $0.trashIDs)
        }
        scanSnapshot = snapshot
        do { try scanStore.save(snapshot) }
        catch { operationError = "Couldn't save duplicate results on this device. \(error.localizedDescription)" }
    }

    func scanForMore() {
        guard !interactionLocked, phase != .scanning else { return }
        allImages = service.fetchAllPhotos()
        phase = .scanning
        Task { await runScan() }
    }

    private func runScan() async {
        scanProgress = 0
        scanUnavailable = 0
        let selected = Set(duplicateGroups.flatMap { $0.trashIDs })
        var snapshot = await finder.scan(allImages, cached: scanSnapshot?.signatures ?? [:]) { [weak self] p, unavailable in
            self?.scanProgress = p
            self?.scanUnavailable = unavailable
        }
        // Preserve explicit selections, but never allow a new grouping to select every member.
        snapshot.groups = snapshot.groups.map { group in
            var result = group
            result.trashIDs = selected.intersection(group.assetIDs)
            return result.retaining(Set(group.assetIDs))!
        }
        scanSnapshot = snapshot
        restoreDuplicateResults()
        phase = .duplicates
        Haptics.success()
    }

    func toggleTrash(group: DuplicateGroup.ID, asset id: String) {
        guard !interactionLocked, let gi = duplicateGroups.firstIndex(where: { $0.id == group }) else { return }
        var g = duplicateGroups[gi]
        if g.trashIDs.contains(id) { g.trashIDs.remove(id) }
        else if g.trashIDs.count < g.assets.count - 1 { g.trashIDs.insert(id) }
        else { Haptics.warning(); return }
        duplicateGroups[gi] = g
        saveDuplicateResults()
        Haptics.soft()
    }
}
