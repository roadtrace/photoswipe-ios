import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

let colors: [UInt8] = (0..<48).map { UInt8(50 + ($0 / 3) * 7) }
func signature(_ h: UInt64 = 0, _ v: UInt64 = 0, _ samples: [UInt8] = colors,
               _ aspect: Double = 1.5) -> DuplicateSignature {
    DuplicateSignature(horizontal: h, vertical: v, colors: samples, aspect: aspect)
}

let original = signature()
expect(original.matches(original), "Identical detailed signatures must match")
expect(original.matches(signature(3, 1, colors.map { $0 + 3 })), "Minor recompression changes should match")
expect(!original.matches(signature(31)), "Different structure must be rejected")
expect(!original.matches(signature(0, 0, colors, 1)), "Different crops/aspect must be rejected")
let shuffled = Array(colors.suffix(24)) + Array(colors.prefix(24))
expect(!original.matches(signature(0, 0, shuffled)), "Same average color with different layout must be rejected")
expect(!signature(0, 0, Array(repeating: 80, count: 48)).matches(
    signature(0, 0, Array(repeating: 80, count: 48))), "Flat gray photos are ambiguous")
let solidRed = Array(repeating: [UInt8(255), UInt8(0), UInt8(0)], count: 16).flatMap { $0 }
expect(!signature(0, 0, solidRed).matches(signature(0, 0, solidRed)), "Flat colored photos are also ambiguous")

// A/B and B/C match, A/C do not: never merge via transitive similarity.
let a = signature(0)
let b = signature(15)
let c = signature(255)
expect(a.matches(b) && b.matches(c) && !a.matches(c), "Chain fixture")
var chain = DuplicateMatcher()
chain.insert(a, index: 0); chain.insert(b, index: 1); chain.insert(c, index: 2)
expect(chain.groups == [[0, 1], [2]], "Transitive near matches must stay separate")

// Duplicates can be arbitrarily far apart; more than the old cap are processed.
var large = DuplicateMatcher()
for index in 0..<2505 { large.insert(original, index: index * 100) }
expect(large.groups.count == 1 && large.groups[0].count == 2505, "No date-window or 2000-photo limit")

// Every <=4-bit horizontal perturbation must be discoverable via the index.
for start in 0..<64 {
    var hash: UInt64 = 0
    for offset in 0..<4 { hash |= UInt64(1) << ((start + offset * 13) % 64) }
    var matcher = DuplicateMatcher()
    matcher.insert(original, index: 0)
    matcher.insert(signature(hash), index: 1)
    expect(matcher.groups == [[0, 1]], "Hash bands must not miss valid matches")
}
print("Duplicate regression checks passed")

// Persistence survives reopening, preserves explicit choices, and drops stale assets.
let revision = PhotoRevision(modified: Date(timeIntervalSince1970: 100), width: 100, height: 100)
let record = CachedPhotoSignature(revision: revision, signature: original)
let savedGroup = SavedDuplicateGroup(assetIDs: ["a", "b", "c"], keeperID: "a", trashIDs: ["b"])
let snapshot = DuplicateScanSnapshot(signatures: ["a": record, "b": record, "c": record],
    groups: [savedGroup], scannedAt: Date(), unavailable: 0)
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let url = directory.appendingPathComponent("scan.json")
let scanStore = DuplicateScanStore(url: url)
try scanStore.save(snapshot)
let reopened = DuplicateScanStore(url: url).load()!
expect(reopened.groups[0].trashIDs == ["b"], "Reopening must preserve deletion selections")
expect(reopened.signatures["a"]?.signature == original, "Reuse persisted fingerprints")
let pruned = reopened.reconciled(with: ["a": revision, "b": revision])
expect(pruned.groups[0].assetIDs == ["a", "b"], "Deleted/inaccessible photos must disappear")
expect(pruned.groups[0].trashIDs == ["b"], "Preserve choices after unrelated deletion")
let edited = PhotoRevision(modified: Date(timeIntervalSince1970: 200), width: 100, height: 100)
let changed = reopened.reconciled(with: ["a": edited, "b": revision, "c": revision])
expect(changed.signatures["a"] == nil, "Edited photos must be re-fingerprinted")
expect(changed.groups[0].keeperID == "b", "Replace inaccessible keeper")
expect(reopened.reconciled(with: ["b": revision]).groups.isEmpty, "Drop singleton groups")
let allSelected = SavedDuplicateGroup(assetIDs: ["a", "b"], keeperID: "a", trashIDs: ["a", "b"])
expect(allSelected.retaining(["a", "b"])!.trashIDs == ["b"], "Reconciliation must keep one photo")
let emptyScan = DuplicateScanSnapshot(signatures: [:], groups: [], scannedAt: Date(), unavailable: 0)
try scanStore.save(emptyScan)
expect(scanStore.load() != nil, "Zero-result scans must also be saved")
try Data("invalid".utf8).write(to: url)
expect(scanStore.load() == nil, "A corrupt cache should allow a fresh scan")
try FileManager.default.removeItem(at: directory)

expect(DeletionSelection.isValid(["b"], reviewed: ["b", "c"], available: ["a", "b", "c"],
    duplicateGroups: [["a", "b", "c"]]), "Reviewed subset can be deleted")
expect(!DeletionSelection.isValid(["x"], reviewed: ["b"], available: ["b", "x"]), "Never expand beyond reviewed photos")
expect(!DeletionSelection.isValid([], reviewed: ["b"], available: ["b"]), "Empty selection must not delete")
expect(!DeletionSelection.isValid(["b"], reviewed: ["b"], available: []), "Revoked or deleted photo blocks confirmation")
expect(!DeletionSelection.isValid(["b"], reviewed: ["b"], available: ["b"],
    duplicateGroups: [["a", "b"]]), "An externally deleted keeper must block deleting the last copy")
expect(!DeletionSelection.isValid(["a", "b"], reviewed: ["a", "b"], available: ["a", "b"],
    duplicateGroups: [["a", "b"]]), "Cannot delete every duplicate")
print("Saved-scan and deletion-safety regression checks passed")
