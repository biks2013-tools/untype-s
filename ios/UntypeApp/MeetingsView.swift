import SwiftUI
import UIKit
import UntypeCore

/// The Meetings tab: one big button records a meeting; the meetings saved
/// on this device are listed below it.
struct MeetingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: MeetingSession
    @EnvironmentObject private var dictation: DictationEngine
    @StateObject private var library = MeetingLibrary()
    @State private var path: [SavedMeeting] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    recordCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                if let problem = session.problem, !session.isActive {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    if library.meetings.isEmpty {
                        Text("No meetings yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(library.meetings) { meeting in
                        NavigationLink(value: meeting) {
                            MeetingRow(meeting: meeting)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            library.delete(library.meetings[index])
                        }
                    }
                } header: {
                    Text("Saved on this device")
                } footer: {
                    Text("Each meeting is a folder in the format of untype on the Mac: open it in untype studio. Share it from the meeting's page, or find it in the Files app (On My iPhone → untype → Meetings).")
                }
            }
            .navigationTitle("Meetings")
            .navigationDestination(for: SavedMeeting.self) { meeting in
                MeetingDetailView(meeting: meeting, library: library)
            }
            .refreshable { library.reload() }
            .onAppear {
                library.reload()
                openSaved()
            }
            .onChange(of: session.savedToOpen) { _, _ in
                library.reload()
                openSaved()
            }
        }
    }

    /// Opens the meeting just saved (the tab may appear only after the save).
    private func openSaved() {
        guard let saved = session.savedToOpen else {
            return
        }
        session.savedToOpen = nil
        path = [saved]
    }

    private var recordCard: some View {
        VStack(spacing: 14) {
            Button {
                Task { await session.start(settings: settings, transcribe: settings.meetingTranscript) }
            } label: {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 96, height: 96)
                            .shadow(color: .red.opacity(0.35), radius: 12, y: 4)
                        Image(systemName: "record.circle")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Text("Record meeting")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
            .disabled(session.isActive || dictation.isBusy)
            .accessibilityLabel("Record meeting")

            Toggle(isOn: $settings.meetingTranscript) {
                Label("Live transcript", systemImage: "text.bubble")
            }
            .padding(.horizontal, 4)
            Text(settings.meetingTranscript
                 ? "You read the transcript as it is written. You can switch it off during the meeting."
                 : "Audio only. You can switch the transcript on during the meeting.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct MeetingRow: View {
    let meeting: SavedMeeting
    @State private var duration: TimeInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(meeting.title ?? "Meeting")
                .font(.body.weight(.medium))
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(meeting.friendlyDate)
                if let duration {
                    Text("·")
                    Text(MeetingRecordingView.clock(duration))
                        .monospacedDigit()
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .task(id: meeting.id) {
            duration = await meeting.duration()
        }
    }
}

/// One saved meeting: its transcript, and Export, Rename, Delete.
struct MeetingDetailView: View {
    @ObservedObject var library: MeetingLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var meeting: SavedMeeting
    @State private var segments: [MeetingSegment] = []
    @State private var follow = false
    @State private var sharing: ShareItem?
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var confirmDelete = false
    @State private var copied = false
    @State private var problem: String?

    init(meeting: SavedMeeting, library: MeetingLibrary) {
        _meeting = State(initialValue: meeting)
        self.library = library
    }

    var body: some View {
        VStack(spacing: 0) {
            if let problem {
                ProblemBanner(problem: problem) { self.problem = nil }
                    .padding(.top, 8)
            }
            if segments.isEmpty {
                ContentUnavailableView(
                    "Audio only",
                    systemImage: "waveform",
                    description: Text("This meeting was recorded without a transcript. untype studio can transcribe the audio.")
                )
            } else {
                MeetingTranscriptView(segments: segments, follow: $follow)
            }
            exportBar
        }
        .navigationTitle(meeting.title ?? meeting.friendlyDate)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        newTitle = meeting.title?.replacingOccurrences(of: "-", with: " ") ?? ""
                        renaming = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task(id: meeting.id) {
            segments = meeting.segments()
        }
        .sheet(item: $sharing) { item in
            ActivityView(items: [item.url])
                .presentationDetents([.medium, .large])
        }
        .alert("Rename the meeting", isPresented: $renaming) {
            TextField("Title", text: $newTitle)
            Button("Rename") {
                if let renamed = library.rename(meeting, to: newTitle) {
                    meeting = renamed
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The folder becomes <title>-\(meeting.stem ?? "recording"), as on the Mac.")
        }
        .confirmationDialog("Delete this meeting?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                library.delete(meeting)
                dismiss()
            }
        } message: {
            Text("The audio and the transcript are removed from this device.")
        }
    }

    private var exportBar: some View {
        HStack(spacing: 12) {
            Button {
                sharing = ShareItem(url: meeting.folder)
            } label: {
                Label("Send folder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                do {
                    sharing = ShareItem(url: try meeting.zipped())
                } catch {
                    problem = "The ZIP file could not be made: \(error.localizedDescription)"
                }
            } label: {
                Label("ZIP", systemImage: "doc.zipper")
            }
            .buttonStyle(.bordered)

            Button {
                UIPasteboard.general.string = meeting.transcriptText()
                copied = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .disabled(segments.isEmpty)
            .accessibilityLabel("Copy the transcript")
        }
        .controlSize(.large)
        .padding(16)
        .background(.bar)
    }
}

struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// The system share sheet (AirDrop to the Mac, Save to Files, Mail, …).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
