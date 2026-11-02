import Foundation

/// Conservative visual similarity, not proof of byte-identical originals.
struct DuplicateSignature: Hashable, Codable {
    let horizontal: UInt64
    let vertical: UInt64
    let colors: [UInt8] // 4 x 4 RGB cells
    let aspect: Double

    func matches(_ other: Self) -> Bool {
        guard aspect > 0, other.aspect > 0,
              abs(log(aspect / other.aspect)) < 0.02,
              colors.count == 48, other.colors.count == 48 else { return false }
        let h = (horizontal ^ other.horizontal).nonzeroBitCount
        let v = (vertical ^ other.vertical).nonzeroBitCount
        guard h <= 4, v <= 4, h + v <= 6 else { return false }
        // Flat images have ambiguous hashes: don't suggest them as duplicates.
        guard hasSpatialDetail, other.hasSpatialDetail else { return false }
        var squaredError = 0
        for (a, b) in zip(colors, other.colors) {
            let delta = Int(a) - Int(b)
            guard abs(delta) <= 24 else { return false }
            squaredError += delta * delta
        }
        return squaredError <= colors.count * 100
    }

    private var hasSpatialDetail: Bool {
        (0..<3).contains { channel in
            let samples = stride(from: channel, to: colors.count, by: 3).map { Int(colors[$0]) }
            return (samples.max() ?? 0) - (samples.min() ?? 0) >= 12
        }
    }

    // <= 4 changed horizontal bits leave at least one of five bands identical.
    var bands: [UInt64] {
        (0..<5).map { band in
            let width = band == 4 ? 12 : 13
            let value = (horizontal >> (band * 13)) & ((UInt64(1) << width) - 1)
            return (UInt64(band) << 16) | value
        }
    }
}

struct DuplicateMatcher {
    private var buckets: [UInt64: Set<Int>] = [:]
    private var signatures: [Set<DuplicateSignature>] = []
    private(set) var groups: [[Int]] = []

    mutating func insert(_ signature: DuplicateSignature, index: Int) {
        guard signature.matches(signature) else { return }
        let candidates = signature.bands.reduce(into: Set<Int>()) {
            $0.formUnion(buckets[$1, default: []])
        }
        // Complete-link matching prevents A~B~C chains grouping unrelated A/C.
        if let group = candidates.sorted().first(where: {
            signatures[$0].allSatisfy { signature.matches($0) }
        }) {
            signatures[group].insert(signature)
            groups[group].append(index)
        } else {
            let group = groups.count
            groups.append([index])
            signatures.append([signature])
            for band in signature.bands { buckets[band, default: []].insert(group) }
        }
    }
}
