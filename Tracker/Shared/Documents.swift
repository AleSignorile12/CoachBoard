import SwiftUI
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import VisionKit
import PDFKit

enum UploadSource { case camera, photos, files }

/// One picker per sheet: SwiftUI misbehaves with several `.fileImporter`s in the same view tree,
/// so every row asks this object and a single modifier on the Form does the presenting.
@Observable
final class DocumentPicker {
    var target: FileKind?
    var showFiles = false
    var showPhotos = false
    var showCamera = false
    var photo: PhotosPickerItem?
    var preview: URL?
    var error: String?
    var renaming: StoredFile?
    /// Bumped after each upload, to trigger a success haptic.
    var uploads = 0
    var newName = ""

    func startRename(_ file: StoredFile) {
        newName = (file.name as NSString).deletingPathExtension
        renaming = file
    }

    /// Keeps the original extension so the file still opens with the right viewer.
    func commitRename() {
        guard let file = renaming else { return }
        renaming = nil
        let typed = newName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !typed.isEmpty else { return }
        let ext = (file.name as NSString).pathExtension
        let keepsExt = ext.isEmpty || (typed as NSString).pathExtension.lowercased() == ext.lowercased()
        file.name = keepsExt ? typed : "\(typed).\(ext)"
    }

    func choose(_ kind: FileKind, from source: UploadSource) {
        target = kind
        switch source {
        case .camera: showCamera = true
        case .photos: showPhotos = true
        case .files: showFiles = true
        }
    }

    /// Quick Look needs a real file, so this writes a temporary copy; `discardPreview` deletes it when the preview closes.
    func open(_ file: StoredFile) {
        do {
            let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: file.name)
            try file.data.write(to: url, options: .completeFileProtection)
            preview = url
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Deletes the temporary copy made by `open` (ID copies and medical certificates shouldn't linger on disk).
    func discardPreview(_ url: URL) {
        // Only ever the UUID folder `open` created directly inside the temporary directory.
        let folder = url.deletingLastPathComponent()
        guard UUID(uuidString: folder.lastPathComponent) != nil,
              folder.deletingLastPathComponent().standardizedFileURL.path() == URL.temporaryDirectory.standardizedFileURL.path()
        else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}

extension View {
    func documentPicker(_ picker: DocumentPicker, onImport: @escaping (FileKind, String, Data) -> Void) -> some View {
        modifier(DocumentPickerModifier(picker: picker) { kind, name, data in
            onImport(kind, name, data)
            picker.uploads += 1
        })
        .sensoryFeedback(.success, trigger: picker.uploads)
    }
}

private struct DocumentPickerModifier: ViewModifier {
    @Bindable var picker: DocumentPicker
    let onImport: (FileKind, String, Data) -> Void

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $picker.showFiles, allowedContentTypes: [.item]) { result in
                guard let kind = picker.target else { return }
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    onImport(kind, url.lastPathComponent, try Data(contentsOf: url))
                } catch {
                    picker.error = error.localizedDescription
                }
            }
            .photosPicker(isPresented: $picker.showPhotos, selection: $picker.photo, matching: .images)
            .onChange(of: picker.photo) { _, item in
                guard let item, let kind = picker.target else { return }
                picker.photo = nil
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { return }
                        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                        onImport(kind, "\(kind.title).\(ext)", data)
                    } catch {
                        picker.error = error.localizedDescription
                    }
                }
            }
            .fullScreenCover(isPresented: $picker.showCamera) {
                DocumentCamera { data in
                    picker.showCamera = false
                    if let data, let kind = picker.target { onImport(kind, "\(kind.title).pdf", data) }
                }
                .ignoresSafeArea()
            }
            .quickLookPreview($picker.preview)
            .onChange(of: picker.preview) { old, new in
                if let old, old != new { picker.discardPreview(old) }
            }
            .alert("Couldn't open file", isPresented: Binding { picker.error != nil } set: { if !$0 { picker.error = nil } }) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(picker.error ?? "")
            }
            .alert("Rename File", isPresented: Binding { picker.renaming != nil } set: { if !$0 { picker.renaming = nil } }) {
                TextField("Name", text: $picker.newName)
                Button("Cancel", role: .cancel) {}
                Button("Rename") { picker.commitRename() }
            }
    }
}

/// An extra file: tap to view, swipe or touch and hold to rename or delete.
struct OtherFileRow: View {
    let file: StoredFile
    let picker: DocumentPicker
    let onDelete: () -> Void

    var body: some View {
        Button { picker.open(file) } label: {
            Label(file.name, systemImage: "doc")
                .lineLimit(1)
        }
        .tint(.primary)
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            Button("Rename", systemImage: "pencil") { picker.startRename(file) }
                .tint(.orange)
        }
        .contextMenu {
            Button("Rename", systemImage: "pencil") { picker.startRename(file) }
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

/// A named upload spot: shows whether it's filled, tap to view, menu to upload / replace / remove.
struct DocumentSlotRow: View {
    let kind: FileKind
    let file: StoredFile?
    let picker: DocumentPicker
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if let file { picker.open(file) } else { picker.choose(kind, from: .files) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: file == nil ? kind.icon : "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(file == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title).foregroundStyle(.primary)
                        Text(file?.name ?? "Not uploaded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            DocumentAddMenu(kind: kind, picker: picker, replacing: file != nil, onDelete: file == nil ? nil : onDelete)
        }
    }
}

/// Upload menu: Photos or Files, plus Remove when there's something to remove.
struct DocumentAddMenu: View {
    let kind: FileKind
    let picker: DocumentPicker
    var replacing = false
    var title: LocalizedStringKey?
    var onDelete: (() -> Void)?

    var body: some View {
        Menu {
            if VNDocumentCameraViewController.isSupported {
                Button("Take Picture", systemImage: "camera") {
                    picker.choose(kind, from: .camera)
                }
            }
            Button(replacing ? "Replace from Photos" : "Choose from Photos", systemImage: "photo.on.rectangle") {
                picker.choose(kind, from: .photos)
            }
            Button(replacing ? "Replace from Files" : "Choose from Files", systemImage: "folder") {
                picker.choose(kind, from: .files)
            }
            if let onDelete {
                Divider()
                Button("Remove", systemImage: "trash", role: .destructive, action: onDelete)
            }
        } label: {
            if let title {
                Label(title, systemImage: "plus.circle.fill")
            } else {
                Image(systemName: replacing ? "ellipsis.circle" : "plus.circle.fill")
                    .font(.title2)
                    .accessibilityLabel(replacing ? "\(kind.title) options" : "Upload \(kind.title)")
            }
        }
    }
}

/// Apple's document camera: takes the picture, crops to the page, and we save every page into one PDF.
struct DocumentCamera: UIViewControllerRepresentable {
    let onFinish: (Data?) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: (Data?) -> Void

        init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pdf = PDFDocument()
            for index in 0..<scan.pageCount {
                if let page = PDFPage(image: scan.imageOfPage(at: index)) { pdf.insert(page, at: pdf.pageCount) }
            }
            onFinish(pdf.pageCount > 0 ? pdf.dataRepresentation() : nil)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onFinish(nil) }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onFinish(nil) }
    }
}
