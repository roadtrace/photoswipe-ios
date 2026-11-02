import Photos

struct DeletionReview: Identifiable {
    enum Source {
        case pending(returnToPicker: Bool)
        case duplicates
    }
    let id = UUID()
    let assets: [PHAsset]
    let source: Source
}

struct PhotoPreview: Identifiable {
    let id = UUID()
    let assets: [PHAsset]
    let initialID: String
}
