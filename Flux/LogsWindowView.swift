// LogsWindowView.swift
// Real-time logs window for debugging

import SwiftUI
import Combine

// MARK: - Log Manager (Singleton)
@MainActor
final class LogManager: ObservableObject {
    static let shared = LogManager()
    
    @Published var logs: [LogEntry] = []
    private let maxLogs = 1000
    
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let level: LogLevel
        
        enum LogLevel: String {
            case info = "INFO"
            case debug = "DEBUG"
            case warning = "WARN"
            case error = "ERROR"
            
            var color: Color {
                switch self {
                case .info: return .primary
                case .debug: return .secondary
                case .warning: return .orange
                case .error: return .red
                }
            }
        }
    }
    
    private init() {}
    
    func log(_ message: String, level: LogEntry.LogLevel = .info) {
        let entry = LogEntry(timestamp: Date(), message: message, level: level)
        logs.append(entry)
        
        // Keep only the last maxLogs entries
        if logs.count > maxLogs {
            logs.removeFirst(logs.count - maxLogs)
        }
        
        // Also print to console
        print("[\(level.rawValue)] \(message)")
    }
    
    func clear() {
        logs.removeAll()
    }
}

// MARK: - Global logging functions
func appLog(_ message: String) {
    Task { @MainActor in
        LogManager.shared.log(message, level: .info)
    }
}

func appLogDebug(_ message: String) {
    Task { @MainActor in
        LogManager.shared.log(message, level: .debug)
    }
}

func appLogWarning(_ message: String) {
    Task { @MainActor in
        LogManager.shared.log(message, level: .warning)
    }
}

func appLogError(_ message: String) {
    Task { @MainActor in
        LogManager.shared.log(message, level: .error)
    }
}

// MARK: - Logs Window View
struct LogsWindowView: View {
    @StateObject private var logManager = LogManager.shared
    @State private var searchText = ""
    @State private var autoScroll = true
    @State private var showDebug = true
    @State private var showInfo = true
    @State private var showWarning = true
    @State private var showError = true
    
    private var filteredLogs: [LogManager.LogEntry] {
        logManager.logs.filter { entry in
            // Filter by level
            switch entry.level {
            case .debug: if !showDebug { return false }
            case .info: if !showInfo { return false }
            case .warning: if !showWarning { return false }
            case .error: if !showError { return false }
            }
            
            // Filter by search text
            if !searchText.isEmpty {
                return entry.message.localizedCaseInsensitiveContains(searchText)
            }
            return true
        }
    }
    
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search logs...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(6)
                .frame(maxWidth: 200)
                
                Divider().frame(height: 20)
                
                // Level filters
                Toggle("DEBUG", isOn: $showDebug)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                
                Toggle("INFO", isOn: $showInfo)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .tint(.primary)
                
                Toggle("WARN", isOn: $showWarning)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .tint(.orange)
                
                Toggle("ERROR", isOn: $showError)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .tint(.red)
                
                Spacer()
                
                // Auto-scroll toggle
                Toggle(isOn: $autoScroll) {
                    Image(systemName: "arrow.down.to.line")
                }
                .toggleStyle(.button)
                .help("Auto-scroll to bottom")
                
                // Clear button
                Button(action: { logManager.clear() }) {
                    Image(systemName: "trash")
                }
                .help("Clear logs")
            }
            .padding(10)
            .background(Color.primary.opacity(0.03))
            
            Divider()
            
            // Logs list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredLogs) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(dateFormatter.string(from: entry.timestamp))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 85, alignment: .leading)
                                
                                Text(entry.level.rawValue)
                                    .font(.system(.caption, design: .monospaced, weight: .bold))
                                    .foregroundStyle(entry.level.color)
                                    .frame(width: 45, alignment: .leading)
                                
                                Text(entry.message)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(entry.level == .error ? .red : .primary)
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .id(entry.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .background(logsBackgroundColor)
                .onChange(of: filteredLogs.count) { _, _ in
                    if autoScroll, let lastLog = filteredLogs.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastLog.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Status bar
            HStack {
                Text("\(filteredLogs.count) logs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if !searchText.isEmpty {
                    Text("Filtered from \(logManager.logs.count) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.03))
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private var logsBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

// MARK: - Window Controller
#if os(macOS)
class LogsWindowController {
    private var window: NSWindow?
    
    static let shared = LogsWindowController()
    
    private init() {}
    
    func showWindow() {
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            Task { @MainActor in
                LogManager.shared.log("Logs window brought to front", level: .info)
            }
            return
        }
        
        Task { @MainActor in
            LogManager.shared.log("Logs window opened - Welcome to Flux Logs!", level: .info)
        }
        
        let contentView = LogsWindowView()
        
        let hostingController = NSHostingController(rootView: contentView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "Flux Logs"
        newWindow.contentViewController = hostingController
        newWindow.center()
        newWindow.setFrameAutosaveName("LogsWindow")
        newWindow.isReleasedWhenClosed = false
        newWindow.makeKeyAndOrderFront(nil)
        
        self.window = newWindow
    }
}
#endif

#Preview {
    LogsWindowView()
        .frame(width: 800, height: 500)
}
