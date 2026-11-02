import Foundation

enum DeletionSelection {
    static func isValid(_ selected: Set<String>, reviewed: Set<String>, available: Set<String>,
                        duplicateGroups: [Set<String>] = []) -> Bool {
        guard !selected.isEmpty, selected.isSubset(of: reviewed), selected.isSubset(of: available)
        else { return false }
        return duplicateGroups.allSatisfy { group in
            let accessible = group.intersection(available)
            return accessible.isDisjoint(with: selected) || !accessible.subtracting(selected).isEmpty
        }
    }
}
