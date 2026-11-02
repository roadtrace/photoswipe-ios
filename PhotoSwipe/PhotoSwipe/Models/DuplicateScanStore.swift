import Foundation

struct PhotoRevision: Codable, Equatable {
    let modified: Date?
    let width: Int
    let height: Int
}

struct CachedPhotoSignature: Codable {
    let revision: PhotoRevision
    let signature: DuplicateSignature
}

struct SavedDuplicateGroup: Codable {
    var assetIDs: [String]
    var keeperID: String
    var trashIDs: Set<String>

    func retaining(_ available: Set<String>) -> Self? {
        let ids = assetIDs.filter { available.contains($0) }
        guard ids.count > 1 else { return nil }
        let keeper = ids.contains(keeperID) ? keeperID : ids[0]
        var selected = trashIDs.intersection(ids)
        if selected.count == ids.count { selected.remove(keeper) }
        return Self(assetIDs: ids, keeperID: keeper, trashIDs: selected)
    }
}

struct DuplicateScanSnapshot: Codable {
    var version = 1
    var signatures: [String: CachedPhotoSignature]
    var groups: [SavedDuplicateGroup]
    var scannedAt: Date
    var unavailable: Int

    func reconciled(with revisions: [String: PhotoRevision]) -> Self {
        var result = self
        result.signatures = signatures.filter { revisions[$0.key] == $0.value.revision }
        let valid = Set(result.signatures.keys)
        result.groups = groups.compactMap { $0.retaining(valid) }
        return result
    }
}

/// Local identifiers and small fingerprints only; never saves photo files.
final class DuplicateScanStore {
    private let url: URL

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory,
            in: .userDomainMask)[0].appendingPathComponent("PhotoSwipe/duplicate-scan.json")
    }

    func load() -> DuplicateScanSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(DuplicateScanSnapshot.self, from: data),
              snapshot.version == 1 else { return nil }
        return snapshot
    }

    func save(_ snapshot: DuplicateScanSnapshot) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                               withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }
}
