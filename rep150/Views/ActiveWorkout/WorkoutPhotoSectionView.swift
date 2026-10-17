import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation

/// Horizontal strip of a session's photos, with an add button that disappears at the cap.
struct WorkoutPhotoSectionView: View {
    @Bindable var session: WorkoutSession
    @Environment(\.modelContext) private var modelContext

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var previewPhoto: WorkoutPhoto?
    @State private var errorMessage: String?
    @State private var isImporting = false
    @State private var isShowingLibrary = false
    @State private var isShowingCamera = false

    private var store: WorkoutStore {
        WorkoutStore(modelContext: modelContext)
    }

    private var photos: [WorkoutPhoto] { session.orderedPhotos }

    private var isAtCap: Bool { !session.canAddPhoto }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Workout Photos")
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                Text("\(photos.count)/\(WorkoutSession.maxPhotoCount)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundColor(isAtCap ? AppColors.packed : .secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if session.canAddPhoto {
                        addButton
                    }

                    ForEach(photos) { photo in
                        thumbnail(for: photo)
                    }
                }
                // Room for the delete badges, which sit outside the thumbnail's bounds.
                .padding(.top, 6)
                .padding(.trailing, 6)
            }
        }
        .onChange(of: selectedItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .sheet(item: $previewPhoto) { photo in
            photoPreview(for: photo)
        }
        .alert(
            "Couldn't Add Photo",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            presenting: errorMessage
        ) { _ in
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Pieces

    private var addButton: some View {
        Menu {
            // Omitted rather than shown-and-broken where there's no camera (the simulator,
            // mainly) — tapping it there would present a dead black sheet.
            if CameraCaptureView.isAvailable {
                Button {
                    requestCamera()
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
            }

            Button {
                isShowingLibrary = true
            } label: {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
            }
        } label: {
            VStack(spacing: 4) {
                if isImporting {
                    ProgressView()
                } else {
                    Image(systemName: "camera.fill")
                        .font(.title3)
                    Text("Add")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
            }
            .foregroundColor(AppColors.brandBlue)
            .frame(width: 80, height: 80)
            .background(Color(.tertiarySystemFill))
            .cornerRadius(12)
        }
        .disabled(isImporting)
        .photosPicker(
            isPresented: $isShowingLibrary,
            selection: $selectedItems,
            // The cap is re-read every time the picker opens, so the user can never select
            // more than the session has room for.
            maxSelectionCount: session.remainingPhotoSlots,
            matching: .images
        )
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraCaptureView { data in
                add(data)
            }
            .ignoresSafeArea()
        }
    }

    private func thumbnail(for photo: WorkoutPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = WorkoutPhotoFileManager.shared.loadImage(filename: photo.filename) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    // The row outlived its file — say so rather than rendering a blank tile.
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 80, height: 80)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture { previewPhoto = photo }

            Button {
                delete(photo)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, AppColors.packed)
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
            .accessibilityLabel("Remove photo")
        }
    }

    private func photoPreview(for photo: WorkoutPhoto) -> some View {
        NavigationStack {
            Group {
                if let image = WorkoutPhotoFileManager.shared.loadImage(filename: photo.filename) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ContentUnavailableView(
                        "Photo Unavailable",
                        systemImage: "photo",
                        description: Text("The image file couldn't be found on this device.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.pageBackground)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { previewPhoto = nil }
                }
            }
        }
    }

    // MARK: - Actions

    /// Checks camera permission before presenting, so a denied app lands on an explanation
    /// instead of the black viewfinder `UIImagePickerController` shows when it can't record.
    private func requestCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isShowingCamera = true

        case .notDetermined:
            Task {
                if await AVCaptureDevice.requestAccess(for: .video) {
                    isShowingCamera = true
                } else {
                    errorMessage = Self.cameraDeniedMessage
                }
            }

        default:
            errorMessage = Self.cameraDeniedMessage
        }
    }

    private static let cameraDeniedMessage =
        "Camera access is turned off. You can turn it back on in Settings › Privacy & Security › Camera."

    /// Saves one image, from either source.
    private func add(_ data: Data) {
        guard session.canAddPhoto else { return }
        do {
            try store.addPhoto(data: data, to: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer {
            isImporting = false
            selectedItems = []
        }

        for item in items {
            guard session.canAddPhoto else { break }

            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    errorMessage = "That photo couldn't be loaded from your library."
                    return
                }
                add(data)
            } catch {
                errorMessage = error.localizedDescription
                return
            }

            // `add` reports its own failures. Stop at the first one rather than grinding
            // through the rest of the selection: a failing disk write fails for every photo,
            // and each pass would overwrite the message with an identical one.
            guard errorMessage == nil else { return }
        }
    }

    private func delete(_ photo: WorkoutPhoto) {
        if previewPhoto?.id == photo.id {
            previewPhoto = nil
        }
        do {
            try store.removePhoto(photo, from: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
