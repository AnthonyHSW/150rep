import SwiftUI
import UIKit

/// The system camera, wrapped for SwiftUI.
///
/// `UIImagePickerController` rather than a hand-rolled `AVCaptureSession`: this is the stock
/// capture UI, and it already handles orientation, flash, and the review step.
struct CameraCaptureView: UIViewControllerRepresentable {
    /// Hands back the captured frame as JPEG data — the same currency the photo-library path
    /// delivers, so both feed one save routine. `Data` also crosses actor boundaries safely
    /// where `UIImage` would not.
    let onCapture: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onFinish: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (Data) -> Void
        private let onFinish: () -> Void

        init(onCapture: @escaping (Data) -> Void, onFinish: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage

            // Encoded at full quality on purpose: the save routine downscales and re-encodes
            // at 0.8, and compressing twice would stack the loss for no gain.
            if let data = image?.jpegData(compressionQuality: 1.0) {
                onCapture(data)
            }
            onFinish()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish()
        }
    }
}
