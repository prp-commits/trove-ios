import SwiftUI
import PhotosUI

/// The capture sheet — the AI ingest path. Note / Photo / Link → POST /api/ingest.
/// Voice is handled by the keyboard's native dictation mic in the Note field.
struct CaptureView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    var onIngested: () -> Void

    enum Mode: String, CaseIterable, Identifiable {
        case text = "Note", photo = "Photo", link = "Link"
        var id: String { rawValue }
    }
    enum Phase {
        case input, working, done(IngestResponse), error(String)
    }

    @State private var mode: Mode = .text
    @State private var text = ""
    @State private var url = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var phase: Phase = .input

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch phase {
                    case .input: inputForm
                    case .working:
                        VStack(spacing: 12) {
                            ProgressView().tint(Theme.ink)
                            Text("Reading and filing…").font(.troveMono(12)).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 60)
                    case .done(let res): result(res)
                    case .error(let message):
                        MessageBlock(title: "Couldn't save that", detail: message) { phase = .input }
                    }
                }
                .padding(20)
            }
            .background(Theme.bg)
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.tint(Theme.ink)
                }
            }
        }
    }

    // MARK: input

    private var inputForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Type", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch mode {
            case .text:
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Jot something about a person or topic — Trove files it for you.")
                            .font(.troveMono(14)).foregroundStyle(Theme.muted)
                            .padding(.top, 14).padding(.horizontal, 12)
                    }
                    TextEditor(text: $text)
                        .font(.troveMono(14))
                        .frame(minHeight: 160)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusField))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusField).stroke(Theme.line, lineWidth: 1))

            case .link:
                TextField("https://…", text: $url)
                    .font(.troveMono(14))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusField))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusField).stroke(Theme.line, lineWidth: 1))
                Text("Trove reads the page and saves what matters.")
                    .font(.troveMono(11)).foregroundStyle(Theme.muted)

            case .photo:
                PhotosPicker(selection: $photoItem, matching: .images) {
                    if let imageData, let ui = UIImage(data: imageData) {
                        Image(uiImage: ui)
                            .resizable().scaledToFill()
                            .frame(height: 200).frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusField))
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 28)).foregroundStyle(Theme.ink2)
                            Text("Choose a photo").font(.troveMono(13)).foregroundStyle(Theme.ink2)
                        }
                        .frame(maxWidth: .infinity).frame(height: 160)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusField))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusField).stroke(Theme.line, lineWidth: 1))
                    }
                }
                .onChange(of: photoItem) { _, newItem in
                    guard let newItem else { return }
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self),
                           let ui = UIImage(data: data),
                           let jpeg = ui.jpegData(compressionQuality: 0.85) {
                            imageData = jpeg
                        }
                    }
                }
                Text("A screenshot, a menu, a whiteboard — Trove pulls out the details.")
                    .font(.troveMono(11)).foregroundStyle(Theme.muted)
            }

            Button("Save to Trove") { Task { await submit() } }
                .buttonStyle(PillButtonStyle(filled: true))
                .disabled(!canSubmit)
                .padding(.top, 4)
        }
    }

    private var canSubmit: Bool {
        switch mode {
        case .text: return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .link: return !url.trimmingCharacters(in: .whitespaces).isEmpty
        case .photo: return imageData != nil
        }
    }

    // MARK: result

    private func result(_ res: IngestResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(res.count == 0 ? "Nothing to save" : "Saved \(res.count) insight\(res.count == 1 ? "" : "s")")
                .font(.troveSerif(24)).foregroundStyle(Theme.ink)

            ForEach(res.insights) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.text).font(.troveMono(13)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        TypeChip(isPerson: item.entity.type == "person")
                        Text(item.entity.name).font(.troveMono(11)).foregroundStyle(Theme.ink2)
                        if item.entity.created == true {
                            Text("· new").font(.troveMono(10)).foregroundStyle(Theme.muted)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line, lineWidth: 1))
            }

            Button("Done") { dismiss() }
                .buttonStyle(PillButtonStyle(filled: true))
                .padding(.top, 4)
            Button("Add another") { reset() }
                .font(.troveMono(13)).foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: actions

    private func submit() async {
        phase = .working
        do {
            let res: IngestResponse
            switch mode {
            case .text:
                res = try await session.ingestText(text)
            case .link:
                res = try await session.ingestURL(url.trimmingCharacters(in: .whitespaces))
            case .photo:
                guard let data = imageData else { phase = .error("Pick a photo first."); return }
                res = try await session.ingestImage(base64: data.base64EncodedString())
            }
            onIngested()
            phase = .done(res)
        } catch {
            phase = .error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func reset() {
        text = ""; url = ""; imageData = nil; photoItem = nil; phase = .input
    }
}
