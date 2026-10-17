import Foundation
import UIKit

/// Owns the JPEGs backing `WorkoutPhoto`, stored in the app sandbox rather than the database.
///
/// Images never go into SwiftData or Postgres as blobs or base64 — only the filename does, so
/// the row stays small and the bytes stay on disk until they're uploaded.
struct WorkoutPhotoFileManager {
    enum PhotoFileError: LocalizedError {
        case unreadableImage
        case encodingFailed
        case directoryUnavailable(Error)
        case writeFailed(Error)

        var errorDescription: String? {
            switch self {
            case .unreadableImage:
                "That file couldn't be read as an image."
            case .encodingFailed:
                "The photo couldn't be prepared for saving."
            case .directoryUnavailable(let error):
                "Couldn't open the photo folder: \(error.localizedDescription)"
            case .writeFailed(let error):
                "Couldn't save the photo: \(error.localizedDescription)"
            }
        }
    }

    /// Longest side of a stored photo, in pixels, and the JPEG quality it's written at.
    private static let maxDimension: CGFloat = 1920
    private static let compressionQuality: CGFloat = 0.8

    static let shared = WorkoutPhotoFileManager()

    private init() {}

    private func photosDirectory() throws -> URL {
        let documents = URL.documentsDirectory
        let directory = documents.appending(path: "WorkoutPhotos", directoryHint: .isDirectory)

        // `withIntermediateDirectories: true` is a no-op when the directory already exists,
        // so this doubles as the existence check.
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw PhotoFileError.directoryUnavailable(error)
        }
        return directory
    }

    func url(for filename: String) throws -> URL {
        try photosDirectory().appending(path: filename, directoryHint: .notDirectory)
    }

    /// Downscales and re-encodes `data`, writes it into the sandbox, and returns the filename
    /// to persist.
    ///
    /// Takes `Data` rather than a `UIImage` on purpose: this is called from an async context,
    /// and `UIImage` isn't `Sendable`, so decoding inside keeps it from crossing an actor
    /// boundary. The whole decode/resize/encode pass stays local to this call.
    func saveImage(data: Data) throws -> String {
        guard let image = UIImage(data: data) else {
            throw PhotoFileError.unreadableImage
        }
        guard let jpeg = image
            .resizedToMaxDimension(Self.maxDimension)
            .jpegData(compressionQuality: Self.compressionQuality)
        else {
            throw PhotoFileError.encodingFailed
        }

        let filename = "\(UUID().uuidString).jpg"
        do {
            try jpeg.write(to: try url(for: filename), options: .atomic)
        } catch let error as PhotoFileError {
            throw error
        } catch {
            throw PhotoFileError.writeFailed(error)
        }
        return filename
    }

    func loadImage(filename: String) -> UIImage? {
        guard let url = try? url(for: filename) else { return nil }
        return UIImage(contentsOfFile: url.path(percentEncoded: false))
    }

    /// Removes the file behind a photo. Best-effort: a missing file is already the goal, and
    /// failing here must not block deleting the metadata the user asked to remove.
    func deleteImage(filename: String) {
        guard let url = try? url(for: filename) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

private extension UIImage {
    /// Scales the image down so its longest side is at most `maxDimension`. Images already
    /// within the limit are returned untouched rather than re-rendered.
    func resizedToMaxDimension(_ maxDimension: CGFloat) -> UIImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension, longestSide > 0 else { return self }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        // `UIGraphicsImageRenderer` defaults to the screen's scale, which would multiply the
        // pixel count back up; format.scale = 1 keeps the output exactly `targetSize` pixels.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
