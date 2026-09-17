import SwiftUI
import AppKit

func bytes(_ n: Int64) -> String {
    let f = ByteCountFormatter(); f.countStyle = .file; f.zeroPadsFractionDigits = false
    return f.string(fromByteCount: n)
}

func displayPath(_ url: URL) -> String {
    let home = NSHomeDirectory()
    return url.path.hasPrefix(home + "/") ? "~" + String(url.path.dropFirst(home.count)) : url.path
}
extension View {
    @ViewBuilder func glassPanel(radius: CGFloat = 20) -> some View {
        if #available(macOS 26.0, *) { self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius)) }
        else { self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius)) }
    }
    func primaryControl() -> some View { self.buttonStyle(GraphiteButtonStyle()) }

}
struct GraphiteButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .foregroundStyle(enabled ? Color.white : Color.secondary)
            .padding(.horizontal, 17).padding(.vertical, 10)
            .background(enabled ? Color(white: configuration.isPressed ? 0.22 : 0.08) : Color.primary.opacity(0.09), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(enabled ? 0.18 : 0.06), lineWidth: 1))
            .shadow(color: .black.opacity(enabled ? 0.10 : 0), radius: 3, y: 2)
    }
}
struct Surface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.06))) }
}
enum ResultSort: String, CaseIterable {
    case size, name, oldest
    var title: String { switch self { case .size: return L("s086"); case .name: return L("s087"); case .oldest: return L("s088") } }
}
@MainActor final class Model: ObservableObject {
    @Published var folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    @Published var threshold: Int64 = 100_000_000
    @Published var enabled = Set(CleanupCategory.allCases.filter { $0 != .developer })
    @Published var category: CleanupCategory?
    @Published var candidates: [Candidate] = []
    @Published var selected: Set<String> = []
    @Published var focused: String?
    @Published var busy = false
    @Published var cleaning = false
    @Published var hasScanned = false
    @Published var completed: Set<CleanupCategory> = []
    @Published var currentCategory: CleanupCategory?
    @Published var notes: [String] = []
    @Published var showNotes = false
    @Published var search = ""
    @Published var sort = ResultSort.size
    @Published var status = L("s089")
    @Published var error: String?
    @Published var confirm = false
    @Published var free: Int64 = 0
    @Published var total: Int64 = 0
    @Published var excluded = Set(UserDefaults.standard.stringArray(forKey: "excludedPaths") ?? [])
    @Published var weeklyEnabled = WeeklySchedule.enabled
    @Published var weeklyBusy = false
    @Published var weeklyConfirm = false
    @Published var weeklyResult = WeeklySchedule.lastResult()
    var worker: Task<AuditResult, Error>?
    var generation = UUID()
    var visible: [Candidate] {
        candidates.filter { item in
            (category == nil || item.category == category) && (search.isEmpty || item.id.localizedCaseInsensitiveContains(search))
        }.sorted { a, b in
            switch sort {
            case .size: return a.entry.size == b.entry.size ? a.id < b.id : a.entry.size > b.entry.size
            case .name: return a.entry.url.lastPathComponent.localizedStandardCompare(b.entry.url.lastPathComponent) == .orderedAscending
            case .oldest: return (a.modified ?? .distantFuture) < (b.modified ?? .distantFuture)
            }
        }
    }
    var picked: [Candidate] { candidates.filter { selected.contains($0.id) } }
    var pickedSize: Int64 { picked.reduce(0) { $0 + $1.entry.size } }
    var foundSize: Int64 { candidates.reduce(0) { $0 + $1.entry.size } }
    var focusedItem: Candidate? { candidates.first { $0.id == focused } }
    var hiddenSelection: Int { selected.subtracting(Set(visible.map(\.id))).count }
    init() { refreshDisk() }
    func refreshDisk() {
        if let a = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            free = (a[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            total = (a[.systemSize] as? NSNumber)?.int64Value ?? 0
        }
    }
    func reset() {
        guard !cleaning else { return }
        cancel(); candidates = []; selected = []; focused = nil; completed = []; hasScanned = false
        search = ""; category = nil; notes = []; error = nil; status = L("s090")
    }
    func cancel() {
        guard !cleaning else { return }
        worker?.cancel(); worker = nil; generation = UUID(); busy = false; currentCategory = nil; status = L("s008")
    }
    func setCategory(_ category: CleanupCategory, enabled value: Bool) {
        guard !busy && !cleaning else { return }
        reset(); if value { enabled.insert(category) } else { enabled.remove(category) }
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = L("s091"); panel.directoryURL = folder
        if panel.runModal() == .OK, let url = panel.url { folder = url; reset() }
    }
    func scan() {
        guard !cleaning, !enabled.isEmpty else { return }
        reset(); busy = true
        let config = AuditConfiguration(folder: folder, threshold: threshold, categories: enabled, excluded: excluded)
        let token = UUID(); generation = token; status = L("s092")
        let task = Task.detached(priority: .userInitiated) { [self] in
            try Audit.scan(config) { category in
                Task { @MainActor [weak self] in
                    guard self?.generation == token, self?.busy == true else { return }
                    self?.currentCategory = category; self?.status = L("s093" , category.title.lowercased())
                }
            }
        }
        worker = task
        Task {
            do {
                let result = try await task.value
                guard generation == token else { return }
                candidates = result.candidates; notes = result.notes; completed = result.completed; hasScanned = true
                status = L("s094" , candidates.count) + (notes.isEmpty ? "" : L("s095"))
            } catch is CancellationError { if generation == token { status = L("s008") } }
              catch { if generation == token { self.error = error.localizedDescription; status = L("s096") } }
            if generation == token { busy = false; worker = nil; currentCategory = nil; refreshDisk() }
        }
    }
    func excludeFocused() {
        guard let item = focusedItem else { return }
        excluded.insert(item.id); UserDefaults.standard.set(Array(excluded), forKey: "excludedPaths")
        candidates.removeAll { $0.id == item.id }; selected.remove(item.id); focused = nil
    }
    func restoreExclusions() { excluded = []; UserDefaults.standard.removeObject(forKey: "excludedPaths"); reset() }
    func trash() {
        guard !cleaning, !busy, !picked.isEmpty else { return }
        let items = picked; cleaning = true; error = nil; status = L("s097")
        Task {
            let result = await Task.detached(priority: .userInitiated) { Audit.trash(items) }.value
            candidates.removeAll { result.removed.contains($0.id) }; selected.subtract(result.removed)
            if let focused, result.removed.contains(focused) { self.focused = nil }
            cleaning = false; refreshDisk()
            status = L("s098" , result.removed.count)
            if !result.failures.isEmpty { error = result.failures.prefix(10).joined(separator: "\n") }
        }
    }
    func setWeekly(_ enabled: Bool) {
        guard !weeklyBusy else { return }; weeklyBusy = true
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LoginItems/MacTidyHelper.app")
        Task {
            do {
                try await Task.detached { if enabled { try WeeklySchedule.enable(helper: helper) } else { try WeeklySchedule.disable() } }.value
            } catch { self.error = error.localizedDescription }
            weeklyEnabled = WeeklySchedule.enabled; weeklyBusy = false; weeklyResult = WeeklySchedule.lastResult()
        }
    }
}
struct ContentView: View {
    @StateObject var m = Model()
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(spacing: 16) {
            header
            overview
            HStack(alignment: .top, spacing: 14) {
                categories.frame(width: 220)
                results.frame(maxWidth: .infinity, maxHeight: .infinity)
                inspector.frame(width: 240)
            }.frame(maxHeight: .infinity)
            bottomBar
        }
        .padding(22).padding(.top, 12)
        .frame(minWidth: 1120, minHeight: 770)
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(colors: [.white.opacity(0.15), .gray.opacity(0.06), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            }.ignoresSafeArea()
        }
        .tint(.primary)
        .onReceive(NotificationCenter.default.publisher(for: .init("MacTidyLanguageUpdated"))) { _ in m.objectWillChange.send() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            m.weeklyEnabled = WeeklySchedule.enabled; m.weeklyResult = WeeklySchedule.lastResult(); m.refreshDisk()
        }
        .alert(L("s099"), isPresented: $m.weeklyConfirm) {
            Button(L("s039"), role: .cancel) {}
            Button(L("s100")) { m.setWeekly(true) }
        } message: { Text(L("s101")) }
        .alert(L("s102"), isPresented: $m.confirm) {
            Button(L("s039"), role: .cancel) {}
            Button(L("s040"), role: .destructive) { m.trash() }
        } message: { Text(L("s103" , m.selected.count, bytes(m.pickedSize), m.hiddenSelection)) }
        .alert(L("s042"), isPresented: Binding(get: { m.error != nil }, set: { if !$0 { m.error = nil } })) {
            Button(L("s043")) { m.error = nil }
        } message: { Text(m.error ?? "") }
    }
    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)).resizable().frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("MacTidy").font(.system(size: 25, weight: .semibold, design: .rounded))
                Text(L("s104")).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button { openWindow(id: "applications") } label: { Label(L("s014"), systemImage: "square.grid.2x2") }.controlSize(.large).buttonStyle(.bordered)
            if m.busy {
                ProgressView().controlSize(.small)
                Button(L("s016"), systemImage: "stop.fill") { m.cancel() }.controlSize(.large).buttonStyle(.bordered)
            } else {
                Button { m.scan() } label: { Label(m.hasScanned ? L("s105") : L("s106"), systemImage: "sparkle.magnifyingglass") }
                    .controlSize(.large).primaryControl().disabled(m.cleaning || m.enabled.isEmpty).keyboardShortcut("r", modifiers: .command)
            }
        }
    }
    private var overview: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Label(L("s107"), systemImage: "internaldrive").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) { Text(bytes(m.free)).font(.system(size: 29, weight: .semibold, design: .rounded)); Text(L("s108" , bytes(m.total))).font(.caption).foregroundStyle(.secondary) }
                ProgressView(value: Double(max(0, m.total - m.free)), total: Double(max(1, m.total))).tint(.primary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Divider().padding(.horizontal, 28)
            VStack(alignment: .leading, spacing: 8) {
                Text(L("s109")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(m.hasScanned ? bytes(m.foundSize) : "—").font(.system(size: 31, weight: .semibold, design: .rounded))
                Text(m.busy ? (m.currentCategory?.title ?? L("s110")) : L("s111" , m.candidates.count)).font(.caption).foregroundStyle(.secondary)
            }.frame(width: 225, alignment: .leading)
            Divider().padding(.horizontal, 28)
            VStack(alignment: .leading, spacing: 8) {
                Label(L("s112"), systemImage: "checkmark.shield").font(.subheadline.weight(.medium))
                Text(L("s113")).font(.callout).foregroundStyle(.secondary)
            }.frame(width: 250, alignment: .leading)
        }.padding(22).frame(height: 120).glassPanel()
    }
    private var categories: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(L("s114")).font(.headline); Spacer(); Text(L("s115" , m.enabled.count)).font(.caption).foregroundStyle(.secondary) }
            Button { m.category = nil } label: {
                HStack { Label(L("s116"), systemImage: "square.grid.2x2.fill"); Spacer(); Text("\(m.candidates.count)").monospacedDigit() }.padding(10)
                    .background(m.category == nil ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain)
            ForEach(CleanupCategory.allCases) { category in
                HStack(spacing: 9) {
                    Toggle(category.title, isOn: Binding(get: { m.enabled.contains(category) }, set: { m.setCategory(category, enabled: $0) }))
                        .labelsHidden().toggleStyle(.checkbox).disabled(m.busy || m.cleaning)
                    Button { m.category = category } label: {
                        HStack(spacing: 10) {
                            Image(systemName: category.symbol).frame(width: 20).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(category.title).font(.system(size: 12, weight: .medium))
                                let total = m.candidates.filter { $0.category == category }.reduce(Int64(0)) { $0 + $1.entry.size }
                                Text(m.completed.contains(category) ? bytes(total) : category.shortDetail).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }.padding(.vertical, 5)
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 9).padding(.vertical, 2)
                    .background(m.category == category ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
            }
            if !m.excluded.isEmpty {
                Button(L("s117" , m.excluded.count)) { m.restoreExclusions() }.font(.caption).disabled(m.busy || m.cleaning)
            }
            Spacer(minLength: 4)
            Text(L("s118")).font(.caption2).foregroundStyle(.secondary)
        }.padding(14).frame(maxHeight: .infinity).glassPanel(radius: 18)
    }
    private var results: some View {
        Surface {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L("s119"), text: $m.search).textFieldStyle(.plain)
                    Picker(L("s120"), selection: $m.sort) { ForEach(ResultSort.allCases, id: \.self) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 140)
                }.padding(14)
                Divider()
                HStack {
                    Text(m.category?.title ?? L("s116")).font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(L("s121")) { m.selected.formUnion(m.visible.map(\.id)) }.disabled(m.visible.isEmpty || m.busy || m.cleaning)
                    Button(L("s028")) { m.selected = [] }.disabled(m.selected.isEmpty || m.cleaning)
                }.font(.caption).padding(.horizontal, 14).padding(.vertical, 10)
                Divider()
                if m.visible.isEmpty { emptyState.frame(maxWidth: .infinity, maxHeight: .infinity) }
                else {
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(m.visible) { item in resultRow(item) }
                        }.padding(6)
                    }
                }
                if m.showNotes && !m.notes.isEmpty {
                    Divider()
                    ScrollView { Text(m.notes.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(12).textSelection(.enabled) }.frame(height: 90)
                }
            }
        }
    }
    private var emptyState: some View {
        VStack(spacing: 14) {
            if m.busy { ProgressView().controlSize(.large) }
            else { Image(systemName: m.hasScanned ? "checkmark.circle" : "sparkles").font(.system(size: 38, weight: .light)).foregroundStyle(.secondary) }
            Text(m.busy ? L("s122") : (m.hasScanned ? L("s123") : L("s124"))).font(.title3.weight(.semibold))
            Text(m.busy ? (m.currentCategory?.title ?? L("s125")) : (m.hasScanned ? L("s126") : L("s127")))
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(20)
    }
    private func resultRow(_ item: Candidate) -> some View {
        HStack(spacing: 10) {
            Toggle(L("s044" , item.entry.url.lastPathComponent), isOn: Binding(get: { m.selected.contains(item.id) }, set: { if $0 { m.selected.insert(item.id) } else { m.selected.remove(item.id) } })).labelsHidden().toggleStyle(.checkbox).disabled(m.cleaning)
            Image(systemName: item.entry.directory ? "folder.fill" : item.category.symbol).font(.system(size: 22)).foregroundStyle(.secondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.entry.url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(displayPath(item.entry.url.deletingLastPathComponent())).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Text(bytes(item.entry.size)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                Text(item.category.title).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }.padding(10).contentShape(Rectangle())
            .background(m.focused == item.id ? Color.primary.opacity(0.10) : (m.selected.contains(item.id) ? Color.primary.opacity(0.045) : .clear), in: RoundedRectangle(cornerRadius: 9))
            .onTapGesture { m.focused = item.id }
            .contextMenu {
                Button(L("s048")) { NSWorkspace.shared.activateFileViewerSelecting([item.entry.url]) }
                Button(L("s128")) { m.focused = item.id; m.excludeFocused() }.disabled(m.cleaning)
            }
    }
    private var inspector: some View {
        VStack(spacing: 12) {
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    Label(L("s129"), systemImage: "slider.horizontal.3").font(.headline)
                    Text(L("s061")).font(.caption).foregroundStyle(.secondary)
                    Button { m.chooseFolder() } label: { Label(displayPath(m.folder), systemImage: "folder").lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading) }.help(m.folder.path)
                    Picker(L("s130"), selection: Binding(get: { m.threshold }, set: { m.threshold = $0; m.reset() })) {
                        Text(L("s131")).tag(Int64(50_000_000)); Text(L("s132")).tag(Int64(100_000_000)); Text(L("s133")).tag(Int64(500_000_000)); Text(L("s134")).tag(Int64(1_000_000_000))
                    }
                }.padding(15).disabled(m.busy || m.cleaning)
            }
            Surface {
                VStack(alignment: .leading, spacing: 10) {
                    if let item = m.focusedItem {
                        Label(item.category.title, systemImage: item.category.symbol).font(.caption).foregroundStyle(.secondary)
                        Text(item.entry.url.lastPathComponent).font(.headline).lineLimit(3)
                        Text(bytes(item.entry.size)).font(.title2.weight(.semibold)).monospacedDigit()
                        if let date = item.modified { Text(L("s135" , date.formatted(date: .abbreviated, time: .omitted))).font(.caption).foregroundStyle(.secondary) }
                        Text(item.category.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button(L("s048"), systemImage: "arrow.up.right.square") { NSWorkspace.shared.activateFileViewerSelecting([item.entry.url]) }.font(.caption)
                        Button(L("s128")) { m.excludeFocused() }.font(.caption).disabled(m.cleaning)
                    } else {
                        Label(L("s136"), systemImage: "info.circle").font(.headline)
                        Text(m.category?.detail ?? L("s137")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(15)
            }
            Spacer(minLength: 0)
            Surface {
                VStack(alignment: .leading, spacing: 9) {
                    Toggle(isOn: Binding(get: { m.weeklyEnabled }, set: { if $0 { m.weeklyConfirm = true } else { m.setWeekly(false) } })) {
                        Text(L("s138")).font(.system(size: 12, weight: .semibold))
                    }.toggleStyle(.switch).controlSize(.small).disabled(m.weeklyBusy || m.cleaning)
                    Text(L("s139")).font(.caption2).foregroundStyle(.secondary)
                    Text(m.weeklyResult).font(.caption2).foregroundStyle(.secondary).lineLimit(2).help(m.weeklyResult)
                }.padding(15)
            }
        }.frame(maxHeight: .infinity)
    }
    private var bottomBar: some View {
        HStack(spacing: 16) {
            if m.cleaning { ProgressView().controlSize(.small) }
            VStack(alignment: .leading, spacing: 4) {
                Text(m.selected.isEmpty ? L("s140") : L("s141" , m.selected.count, bytes(m.pickedSize))).font(.subheadline.weight(.semibold))
                Text(m.hiddenSelection > 0 ? L("s142" , m.hiddenSelection) : m.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if !m.notes.isEmpty { Button { m.showNotes.toggle() } label: { Label(L("s036" , m.notes.count), systemImage: "exclamationmark.circle") }.font(.caption) }
            Button { m.confirm = true } label: { Label(L("s037"), systemImage: "trash") }.controlSize(.large).primaryControl()
                .disabled(m.selected.isEmpty || m.busy || m.cleaning)
        }.padding(16).glassPanel(radius: 18)
    }
}
#if !TESTING
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "MacTidyGraphite", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = icon
        }
    }
}
@main struct MacTidy: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Window("MacTidy", id: "main") { LocalizedRoot(translates: true) { ContentView() } }.windowStyle(.hiddenTitleBar).defaultSize(width: 1260, height: 860)
        Window(L("s143"), id: "applications") { LocalizedRoot(translates: false) { ApplicationsView() } }.windowStyle(.hiddenTitleBar).defaultSize(width: 1050, height: 740)
    }
}
#endif
