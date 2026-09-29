import Photos
import PhotosUI
import SwiftUI

/// Chosen media before the place is saved.
struct PickedMedia: Identifiable, Hashable {
    let id = UUID()
    let kind: MediaKind
    /// `PHAsset.localIdentifier` — with library access, only this is stored.
    let localIdentifier: String?
    /// A copy of the bytes — when there is no library access.
    let data: Data?
    let takenAt: Date?
}

/// Multi-selection of photos and videos via `PHPickerViewController`.
struct PhotoPicker: UIViewControllerRepresentable {
    let photoService: PhotoService
    let onPicked: ([PickedMedia]) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = 0
        configuration.filter = .any(of: [.images, .videos])
        configuration.preferredAssetRepresentationMode = .current

        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: PhotoPicker

        init(parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            let identifiers = results.compactMap(\.assetIdentifier)
            let providers = results.map(\.itemProvider)

            Task { @MainActor in
                let picked = await Self.resolve(identifiers: identifiers,
                                                providers: providers,
                                                photoService: parent.photoService)
                parent.onPicked(picked)
                parent.dismiss()
            }
        }

        /// With library access we store `localIdentifier` and do not copy bytes.
        /// Without it we copy the data, otherwise the media cannot be shown.
        @MainActor
        private static func resolve(identifiers: [String],
                                    providers: [NSItemProvider],
                                    photoService: PhotoService) async -> [PickedMedia] {
            let authorization = await photoService.authorization
            let effective = authorization == .notDetermined
                ? await photoService.requestAuthorization()
                : authorization

            if effective.allowsReading, !identifiers.isEmpty {
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
                var result: [PickedMedia] = []
                assets.enumerateObjects { asset, _, _ in
                    result.append(PickedMedia(
                        kind: asset.mediaType == .video ? .video : .photo,
                        localIdentifier: asset.localIdentifier,
                        data: nil,
                        takenAt: asset.creationDate
                    ))
                }
                if !result.isEmpty { return result }
            }

            return await copyData(from: providers)
        }

        @MainActor
        private static func copyData(from providers: [NSItemProvider]) async -> [PickedMedia] {
            var result: [PickedMedia] = []
            for provider in providers {
                let isVideo = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
                let type: UTType = isVideo ? .movie : .image
                guard provider.hasItemConformingToTypeIdentifier(type.identifier),
                      let data = await provider.loadData(for: type)
                else { continue }

                result.append(PickedMedia(kind: isVideo ? .video : .photo,
                                          localIdentifier: nil,
                                          data: data,
                                          takenAt: nil))
            }
            return result
        }
    }
}

private extension NSItemProvider {
    // NSItemProvider isn't Sendable — keep it on the main actor.
    @MainActor
    func loadData(for type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            // loadDataRepresentation calls the handler exactly once.
            loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
