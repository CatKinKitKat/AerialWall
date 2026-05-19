import SwiftUI
import OSLog

@MainActor
@Observable
final class LogStream {
    var entries: [LogEntry] = []
    var isLoading = false
    var error: String?
    var sinceMinutes: Int = 60

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            // Fallback to .system scope if .currentProcessIdentifier returns empty
            // (works for previously-launched processes in this user's session).
            let position = store.position(date: Date().addingTimeInterval(-Double(sinceMinutes * 60)))
            let predicate = NSPredicate(format: "subsystem == %@", "com.aerialwall.kit")
            let raw = try store.getEntries(at: position, matching: predicate)

            var out: [LogEntry] = []
            for entry in raw {
                guard let log = entry as? OSLogEntryLog else { continue }
                out.append(LogEntry(
                    date: log.date,
                    level: LogLevel(osLogLevel: log.level),
                    category: log.category,
                    message: log.composedMessage))
            }
            entries = out.reversed()           // newest first
            error = nil
        } catch {
            self.error = "\(error)"
        }
    }
}

struct LogEntry: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let level: LogLevel
    let category: String
    let message: String
}

enum LogLevel: String, CaseIterable, Hashable {
    case debug, info, notice, error, fault
    init(osLogLevel level: OSLogEntryLog.Level) {
        switch level {
        case .debug:  self = .debug
        case .info:   self = .info
        case .notice: self = .notice
        case .error:  self = .error
        case .fault:  self = .fault
        case .undefined: self = .info
        @unknown default: self = .info
        }
    }
    var color: Color {
        switch self {
        case .debug:  return .secondary
        case .info:   return .primary
        case .notice: return .blue
        case .error:  return .orange
        case .fault:  return .red
        }
    }
    var symbol: String {
        switch self {
        case .debug:  return "ladybug"
        case .info:   return "info.circle"
        case .notice: return "bell"
        case .error:  return "exclamationmark.triangle"
        case .fault:  return "xmark.octagon"
        }
    }
}

struct LogView: View {
    @State private var stream = LogStream()
    @State private var levelFilter: Set<LogLevel> = [.info, .notice, .error, .fault]
    @State private var searchText = ""

    private var filtered: [LogEntry] {
        stream.entries.filter { entry in
            guard levelFilter.contains(entry.level) else { return false }
            if !searchText.isEmpty {
                return entry.message.localizedCaseInsensitiveContains(searchText)
                    || entry.category.localizedCaseInsensitiveContains(searchText)
            }
            return true
        }
    }

    var body: some View {
        Group {
            if stream.entries.isEmpty && !stream.isLoading {
                emptyState
            } else {
                logList
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Range", selection: $stream.sinceMinutes) {
                    Text("Last 5 min").tag(5)
                    Text("Last 15 min").tag(15)
                    Text("Last 1 hour").tag(60)
                    Text("Last 6 hours").tag(360)
                    Text("Last 24 hours").tag(1440)
                }
                .pickerStyle(.menu)
                .onChange(of: stream.sinceMinutes) { _, _ in
                    Task { await stream.refresh() }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await stream.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(stream.isLoading)
            }
        }
        .searchable(text: $searchText, prompt: "Filter logs…")
        .navigationTitle("Logs")
        .task { await stream.refresh() }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No log entries", systemImage: "terminal")
        } description: {
            if let err = stream.error {
                Text("Couldn't read logs: \(err)")
            } else {
                Text("No `com.aerialwall.kit` log entries in the selected window. Import or apply a wallpaper to generate some.")
            }
        } actions: {
            Button("Refresh") { Task { await stream.refresh() } }
        }
    }

    private var logList: some View {
        VStack(spacing: 0) {
            levelFilterBar
            Divider()
            Table(filtered) {
                TableColumn("") { entry in
                    Image(systemName: entry.level.symbol)
                        .foregroundStyle(entry.level.color)
                }
                .width(20)
                TableColumn("Time") { entry in
                    Text(entry.date, format: .dateTime.hour().minute().second())
                        .monospacedDigit()
                        .font(.caption)
                }
                .width(80)
                TableColumn("Category") { entry in
                    Text(entry.category)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .width(110)
                TableColumn("Message") { entry in
                    Text(entry.message)
                        .font(.callout)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var levelFilterBar: some View {
        HStack(spacing: 8) {
            ForEach(LogLevel.allCases, id: \.self) { level in
                Toggle(isOn: Binding(
                    get: { levelFilter.contains(level) },
                    set: { isOn in
                        if isOn { levelFilter.insert(level) }
                        else { levelFilter.remove(level) }
                    }
                )) {
                    Label(level.rawValue, systemImage: level.symbol)
                        .foregroundStyle(level.color)
                }
                .toggleStyle(.button)
                .controlSize(.small)
            }
            Spacer()
            Text("\(filtered.count) entries")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
