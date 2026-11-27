import SwiftUI
import SwiftData
import PhotosUI

struct CoachProfileSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var coaches: [Coach]

    var body: some View {
        NavigationStack {
            Group {
                if let coach = coaches.first {
                    CoachForm(coach: coach)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("My Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .onAppear {
            if coaches.isEmpty { context.insert(Coach()) }
        }
    }
}

private struct CoachForm: View {
    @Bindable var coach: Coach
    @Environment(\.modelContext) private var context
    @State private var picker = DocumentPicker()
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhoto = false
    @State private var showTour = false
    @Namespace private var photoZoom

    private var idFile: StoredFile? { coach.files?.first { $0.kind == .coachID } }

    private var otherFiles: [StoredFile] {
        (coach.files ?? []).filter { $0.kind == .other }.sorted { $0.addedAt < $1.addedAt }
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    ZStack(alignment: .bottomTrailing) {
                        if coach.photo != nil {
                            // Tap to see the picture full screen (it zooms out of the circle).
                            Button { showPhoto = true } label: { avatar }
                                .buttonStyle(.plain)
                                .matchedTransitionSource(id: "photo", in: photoZoom)
                                .accessibilityLabel("View profile picture")
                        } else {
                            PhotosPicker(selection: $photoItem, matching: .images) { avatar }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Add profile picture")
                        }
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Image(systemName: "camera.circle.fill")
                                .font(.title)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .tint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(coach.photo == nil ? "Add profile picture" : "Change profile picture")
                    }
                    .contextMenu {
                        if coach.photo != nil {
                            Button("Remove Picture", systemImage: "trash", role: .destructive) { coach.photo = nil }
                        }
                    }
                    .fullScreenCover(isPresented: $showPhoto) {
                        PhotoViewer(coach: coach, photoItem: $photoItem)
                            .navigationTransition(.zoom(sourceID: "photo", in: photoZoom))
                    }
                    Text("\(coach.firstName) \(coach.lastName)".trimmingCharacters(in: .whitespaces).isEmpty
                         ? "Coach" : "\(coach.firstName) \(coach.lastName)")
                        .font(.title2.bold())
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("Details") {
                TextField("First Name", text: $coach.firstName)
                    .textContentType(.givenName)
                TextField("Last Name", text: $coach.lastName)
                    .textContentType(.familyName)
                TextField("Phone", text: $coach.phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                TextField("Email", text: $coach.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if coach.birthDate != nil {
                    DatePicker("Date of Birth",
                               selection: Binding { coach.birthDate ?? .now } set: { coach.birthDate = $0 },
                               in: ...Date.now, displayedComponents: .date)
                } else {
                    Button("Add Date of Birth", systemImage: "birthday.cake") {
                        coach.birthDate = Calendar.current.date(byAdding: .year, value: -30, to: .now)
                    }
                }
            }

            Section {
                AppLanguageRow()
                SportPicker()
                NavigationLink {
                    FeeSettingsView()
                } label: {
                    Label("Fees", systemImage: "eurosign.circle")
                }
                Button("Welcome Tour", systemImage: "sparkles") { showTour = true }
            } header: {
                Text("App")
            } footer: {
                Text("CoachBoard uses your iPhone's language. To pick a different one just for CoachBoard, choose Language in Settings.")
            }

            Section {
                ICloudStatusRow()
            } footer: {
                Text("Kids, payments, files and the practice log are saved in your iCloud and stay in sync on your devices, even if you delete the app.")
            }

            Section {
                AppLockRow()
            } footer: {
                Text("CoachBoard asks for Face ID or your passcode every time you open it, and stays hidden in the app switcher.")
            }

            Section("ID") {
                DocumentSlotRow(kind: .coachID, file: idFile, picker: picker) {
                    if let idFile { context.delete(idFile) }
                }
            }

            Section {
                ForEach(otherFiles) { file in
                    OtherFileRow(file: file, picker: picker) { context.delete(file) }
                }
                DocumentAddMenu(kind: .other, picker: picker, title: "Add File")
            } header: {
                Text("Other Files")
            } footer: {
                Text("Swipe a file to rename or delete it.")
            }
        }
        .sheet(isPresented: $showTour) {
            OnboardingView(isReplay: true) { showTour = false }
        }
        .documentPicker(picker) { kind, name, data in
            context.storeFile(kind, name: name, data: data, coach: coach)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                defer { photoItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    picker.error = String(localized: "This photo couldn't be loaded.")
                    return
                }
                // 1600 px: sharp full screen, still small to store.
                let width = min(1600, image.size.width)
                let size = CGSize(width: width, height: width * image.size.height / max(image.size.width, 1))
                coach.photo = (image.preparingThumbnail(of: size) ?? image).jpegData(compressionQuality: 0.85)
            }
        }
    }

    private var avatar: some View {
        Group {
            if let data = coach.photo, let image = UIImage(data: data) {
                // The photo inside a blue ring, with a thin gap between them.
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: 88, height: 88)
                    .clipShape(.circle)
                    .padding(4)
                    .overlay { Circle().strokeBorder(.tint, lineWidth: 3) }
            } else {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.tint)
            }
        }
        .frame(width: 96, height: 96)
    }
}

/// Full-screen profile picture: pinch or double-tap to zoom, drag when zoomed, swipe down to close.
private struct PhotoViewer: View {
    let coach: Coach
    @Binding var photoItem: PhotosPickerItem?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let data = coach.photo, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(zoom)
                        // Panning only while zoomed, so swipe-down-to-close keeps working at normal size.
                        .gesture(pan, including: scale > 1 ? .all : .subviews)
                        .onTapGesture(count: 2) { withAnimation(.snappy) { scale > 1 ? reset() : zoomIn() } }
                        .accessibilityLabel("Profile picture")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Change Picture", systemImage: "photo.on.rectangle")
                        }
                        Button("Remove Picture", systemImage: "trash", role: .destructive) {
                            coach.photo = nil
                            dismiss()
                        }
                    } label: {
                        Label("Edit", systemImage: "ellipsis")
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { scale = min(max(lastScale * $0.magnification, 1), 5) }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 { withAnimation(.snappy) { reset() } }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { offset = CGSize(width: lastOffset.width + $0.translation.width,
                                         height: lastOffset.height + $0.translation.height) }
            .onEnded { _ in lastOffset = offset }
    }

    private func zoomIn() {
        scale = 2.5
        lastScale = 2.5
    }

    private func reset() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}
