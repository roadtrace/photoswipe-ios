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
let solidRed = Array(repeating: [UInt8(255), 0, 0], count: 16).flatMap { $0 }
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
