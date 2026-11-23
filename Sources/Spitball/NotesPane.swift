import AppKit
import Observation
import SwiftUI

/// Voice notes and meeting notes: record, read the summary, copy as Markdown.
struct NotesPane: View {
    var store: Store
    var taker = Notetaker.shared
    let theme: RetroTheme
    @State private var open: Note.ID?
    @State private var query = ""

    var items: [Note] {
        query.isEmpty ? store.notes : store.notes.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.transcript.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        if let id = open, let note = store.notes.first(where: { $0.id == id }) {
            NoteDetail(note: note, theme: theme, back: { open = nil }, delete: {
                store.notes.removeAll { $0.id == id }; open = nil
            })
        } else {
            list
        }
    }

    var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            PaneIntro(theme: theme, text: "Record a thought or a whole call. No bot joins your meeting: Spitball hears your mic and your Mac's audio, then writes the summary on your Mac.")
            HStack(spacing: 8) {
                recordButton(.voice, "New voice note", "mic.fill", "⌃⌘N")
                recordButton(.meeting, "Meeting notes", "person.2.fill", "⌃⌘M")
                Spacer()
            }
            .padding(.horizontal, 12)
            if let live = taker.current { LiveNoteCard(note: live, elapsed: taker.elapsed, finishing: taker.finishing, theme: theme) { taker.stop() } }
            if let e = taker.lastError { Text(e).font(RetroFont.body(11)).foregroundStyle(.red).padding(.horizontal, 12) }
            if !store.notes.isEmpty {
                RetroField(theme: theme, placeholder: "Search your notes…", text: $query).padding(.horizontal, 12)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { n in
                        Button { open = n.id } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: n.kind == .meeting ? "person.2.fill" : "mic.fill")
                                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.ink.opacity(0.6)).frame(width: 18, height: 18)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(n.title).font(RetroFont.title(13)).foregroundStyle(theme.ink).lineLimit(1)
                                    Text("\(n.date.formatted(date: .abbreviated, time: .shortened)) · \(Note.clock(n.duration))\((n.app.map { " · " + $0 }) ?? "")")
                                        .font(RetroFont.body(11)).foregroundStyle(theme.ink.opacity(0.55))
                                    if let first = n.summary.first {
                                        Text(first).font(RetroFont.body(12)).foregroundStyle(theme.ink.opacity(0.75)).lineLimit(2)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.ink.opacity(0.35))
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(n.title), \(n.kind == .meeting ? "meeting" : "voice note"), \(n.date.formatted())")
                        Rectangle().fill(theme.ink.opacity(Skin.isPro ? 0.07 : 0.2)).frame(height: 1)
                    }
                    if store.notes.isEmpty && taker.current == nil {
                        Text("No notes yet. Press ⌃⌘N anywhere to start one.")
                            .font(RetroFont.body(12)).foregroundStyle(theme.ink.opacity(0.5)).padding(12)
                    }
                }
            }
        }
    }

    func recordButton(_ kind: Note.Kind, _ title: String, _ icon: String, _ key: String) -> some View {
        let active = taker.current?.kind == kind
        return Button { taker.toggle(kind) } label: {
            HStack(spacing: 6) {
                Image(systemName: active ? "stop.fill" : icon).font(.system(size: 11, weight: .bold))
                Text(active ? "Stop" : title)
                Text(key).opacity(0.5)
            }
        }
        .buttonStyle(RetroButtonStyle(theme: theme, filled: active))
        .disabled(taker.finishing || (taker.current != nil && !active))
    }
}

struct LiveNoteCard: View {
    let note: Note
    let elapsed: Double
    let finishing: Bool
    let theme: RetroTheme
    let stop: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(finishing ? Color.gray : Color.red).frame(width: 8, height: 8)
                Text(finishing ? "Writing up your note…" : (note.kind == .meeting ? "Taking meeting notes" : "Recording")).font(RetroFont.title(12)).foregroundStyle(theme.ink)
                Text(Note.clock(elapsed)).font(RetroFont.mono(12)).foregroundStyle(theme.ink.opacity(0.6))
                Spacer()
                if !finishing { Button("Stop", action: stop).buttonStyle(RetroButtonStyle(theme: theme, filled: true)) }
            }
            ForEach(note.lines.suffix(3)) { l in
                Text((note.kind == .meeting ? "\(l.speaker): " : "") + l.text).font(RetroFont.body(12)).foregroundStyle(theme.ink.opacity(0.8)).lineLimit(2)
            }
            if note.lines.isEmpty && !finishing {
                Text("Transcript appears here as you talk (every ~20 seconds).").font(RetroFont.body(11)).foregroundStyle(theme.ink.opacity(0.5))
            }
        }
        .padding(12)
        .background(Skin.isPro ? AnyView(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.965))) : AnyView(theme.paper.overlay(Rectangle().strokeBorder(theme.ink, lineWidth: 1.5))))
        .padding(.horizontal, 12)
    }
}

struct NoteDetail: View {
    let note: Note
    let theme: RetroTheme
    let back: () -> Void
    let delete: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button { back() } label: { Label("Notes", systemImage: "chevron.left") }.buttonStyle(RetroButtonStyle(theme: theme))
                Spacer()
                Button(copied ? "Copied" : "Copy as Markdown") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(note.markdown, forType: .string)
                    copied = true; DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                }.buttonStyle(RetroButtonStyle(theme: theme, filled: copied))
                Button("Export…") { export() }.buttonStyle(RetroButtonStyle(theme: theme))
                Button(role: .destructive) { delete() } label: { Image(systemName: "trash") }.buttonStyle(RetroButtonStyle(theme: theme))
                    .accessibilityLabel("Delete note")
            }
            .padding(.horizontal, 12).padding(.bottom, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(note.title).font(RetroFont.title(18)).foregroundStyle(theme.ink).textSelection(.enabled)
                    Text("\(note.date.formatted(date: .complete, time: .shortened)) · \(Note.clock(note.duration)) · \(note.words) words")
                        .font(RetroFont.body(11)).foregroundStyle(theme.ink.opacity(0.55))
                    if !note.summary.isEmpty { section("Summary", note.summary.map { "• " + $0 }) }
                    if !note.actions.isEmpty { section("Action items", note.actions.map { "☐ " + $0 }) }
                    Text("TRANSCRIPT").font(RetroFont.title(10)).tracking(0.8).foregroundStyle(theme.ink.opacity(0.5))
                    ForEach(note.lines) { l in
                        HStack(alignment: .top, spacing: 8) {
                            Text(Note.clock(l.at)).font(RetroFont.mono(10)).foregroundStyle(theme.ink.opacity(0.4)).frame(width: 40, alignment: .leading)
                            if note.kind == .meeting {
                                Text(l.speaker).font(RetroFont.title(11)).foregroundStyle(l.speaker == "You" ? theme.ink : theme.ink.opacity(0.6)).frame(width: 40, alignment: .leading)
                            }
                            Text(l.text).font(RetroFont.body(13)).foregroundStyle(theme.ink).textSelection(.enabled)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    func section(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(RetroFont.title(10)).tracking(0.8).foregroundStyle(theme.ink.opacity(0.5))
            ForEach(lines, id: \.self) { Text($0).font(RetroFont.body(13)).foregroundStyle(theme.ink).textSelection(.enabled) }
        }
    }

    func export() {
        let p = NSSavePanel()
        p.nameFieldStringValue = note.title.replacingOccurrences(of: "/", with: "-") + ".md"
        p.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        if p.runModal() == .OK, let url = p.url { try? note.markdown.write(to: url, atomically: true, encoding: .utf8) }
    }
}
