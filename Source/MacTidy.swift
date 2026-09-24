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
@MainActor final class CleanupUIState: ObservableObject {
    @Published var showSettings = false
}
struct ContentView: View {
    @StateObject private var m = Model()
    @StateObject private var ui = CleanupUIState()
    @StateObject private var updater = UpdateModel()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 22) {
            header
            if updater.available != nil { updateBanner }
            if !m.hasScanned && !m.busy { welcome }
            else { review }
        }
        .padding(28)
        .frame(minWidth: 760, minHeight: 620)
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(colors: [.white.opacity(0.15), .gray.opacity(0.05), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            }.ignoresSafeArea()
        }
        .tint(.primary)
        .sheet(isPresented: $ui.showSettings) { settings }
        .task { await updater.check(automatic: true) }
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
        } message: { Text(L("s103", m.selected.count, bytes(m.pickedSize), m.hiddenSelection)) }
        .alert(L("s042"), isPresented: Binding(get: { m.error != nil }, set: { if !$0 { m.error = nil } })) {
            Button(L("s043")) { m.error = nil }
        } message: { Text(m.error ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable().frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("MacTidy").font(.system(size: 23, weight: .semibold, design: .rounded))
                Text(L("s104")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { openWindow(id: "storage") } label: {
                Image(systemName: "internaldrive").font(.system(size: 17)).frame(width: 30, height: 30)
            }.buttonStyle(.plain).help(L("s164")).accessibilityLabel(L("s164"))
            Button { openWindow(id: "applications") } label: {
                Image(systemName: "square.grid.2x2").font(.system(size: 17)).frame(width: 30, height: 30)
            }.buttonStyle(.plain).help(L("s014")).accessibilityLabel(L("s014"))
            Button { ui.showSettings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 17)).frame(width: 30, height: 30)
            }.buttonStyle(.plain).help(L("s129")).accessibilityLabel(L("s129"))
        }
    }

    private var updateBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle").font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("s152", updater.available?.version.description ?? "")).font(.subheadline.weight(.semibold))
                if let message = updater.message { Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer()
            if updater.busy { ProgressView().controlSize(.small) }
            else {
                Button(L("s154")) { Task { await updater.install() } }.primaryControl()
            }
        }.padding(15).glassPanel(radius: 17)
    }

    private var diskSummary: some View {
        VStack(spacing: 14) {
            Image(systemName: "internaldrive").font(.system(size: 28, weight: .ultraLight)).foregroundStyle(.secondary)
            Text(bytes(m.free)).font(.system(size: 43, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(L("s108", bytes(m.total))).font(.callout).foregroundStyle(.secondary)
            ProgressView(value: Double(max(0, m.total - m.free)), total: Double(max(1, m.total)))
                .tint(.primary).frame(maxWidth: 340)
            Text(L("s107")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            diskSummary
            Spacer(minLength: 25)
            Text(L("s124")).font(.system(size: 24, weight: .semibold, design: .rounded))
            Text(L("s113")).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.top, 9)
            Button { m.scan() } label: {
                Label(L("s106"), systemImage: "sparkle.magnifyingglass")
                    .frame(minWidth: 230).padding(.vertical, 4)
            }
            .buttonStyle(GraphiteButtonStyle()).controlSize(.large)
            .disabled(m.enabled.isEmpty)
            .keyboardShortcut("r", modifiers: .command)
            .padding(.top, 28)
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassPanel(radius: 24)
    }

    private var review: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.busy ? L("s122") : L("s109")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text(m.busy ? "…" : bytes(m.foundSize)).font(.system(size: 34, weight: .semibold, design: .rounded))
                }
                Spacer()
                Text(m.busy ? (m.currentCategory?.title ?? L("s125")) : L("s111", m.candidates.count))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                if m.busy {
                    Button(L("s016"), systemImage: "stop.fill") { m.cancel() }.buttonStyle(.bordered)
                } else {
                    Button { m.scan() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).help(L("s105")).accessibilityLabel(L("s105"))
                        .disabled(m.cleaning).keyboardShortcut("r", modifiers: .command)
                }
            }
            if m.busy { ProgressView().controlSize(.small) }
            resultList
            if m.hasScanned { actionBar }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultList: some View {
        Surface {
            VStack(spacing: 0) {
                if m.hasScanned {
                    HStack(spacing: 14) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(L("s119"), text: $m.search).textFieldStyle(.plain)
                        Menu {
                            Button(L("s116")) { m.category = nil }
                            Divider()
                            ForEach(CleanupCategory.allCases) { category in
                                Button(category.title) { m.category = category }
                            }
                        } label: {
                            Label(m.category?.title ?? L("s116"), systemImage: "line.3.horizontal.decrease")
                        }.menuStyle(.borderlessButton).fixedSize().help(L("s114"))
                        Picker(L("s120"), selection: $m.sort) {
                            ForEach(ResultSort.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.labelsHidden().frame(width: 120)
                    }.padding(.horizontal, 18).padding(.vertical, 14)
                    Divider()
                }
                if m.visible.isEmpty {
                    VStack(spacing: 13) {
                        if m.busy { ProgressView().controlSize(.large) }
                        else { Image(systemName: "checkmark.circle").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(.secondary) }
                        Text(m.busy ? L("s122") : L("s123")).font(.title3.weight(.semibold))
                        Text(m.busy ? (m.currentCategory?.title ?? L("s125")) : L("s126"))
                            .font(.callout).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) { ForEach(m.visible) { item in resultRow(item) } }
                            .padding(9)
                    }
                }
                if let item = m.focusedItem {
                    Divider()
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.entry.url.lastPathComponent).font(.callout.weight(.medium)).lineLimit(1)
                            Text(displayPath(item.entry.url)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button(L("s048")) { NSWorkspace.shared.activateFileViewerSelecting([item.entry.url]) }.font(.caption)
                        Button(L("s128")) { m.excludeFocused() }.font(.caption).disabled(m.cleaning)
                    }.padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
        }
    }

    private func resultRow(_ item: Candidate) -> some View {
        HStack(spacing: 13) {
            Toggle(L("s044", item.entry.url.lastPathComponent), isOn: Binding(
                get: { m.selected.contains(item.id) },
                set: { if $0 { m.selected.insert(item.id) } else { m.selected.remove(item.id) } }
            )).labelsHidden().toggleStyle(.checkbox).disabled(m.cleaning)
            Image(systemName: item.entry.directory ? "folder.fill" : item.category.symbol)
                .font(.system(size: 20)).foregroundStyle(.secondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.entry.url.lastPathComponent).font(.callout.weight(.medium)).lineLimit(1)
                Text(displayPath(item.entry.url.deletingLastPathComponent())).font(.caption)
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 5)
            Text(bytes(item.entry.size)).font(.callout.weight(.semibold)).monospacedDigit()
        }
        .padding(11).contentShape(Rectangle())
        .background(m.focused == item.id ? Color.primary.opacity(0.10) :
                    (m.selected.contains(item.id) ? Color.primary.opacity(0.045) : .clear),
                    in: RoundedRectangle(cornerRadius: 11))
        .onTapGesture { m.focused = item.id }
        .contextMenu {
            Button(L("s048")) { NSWorkspace.shared.activateFileViewerSelecting([item.entry.url]) }
            Button(L("s128")) { m.focused = item.id; m.excludeFocused() }.disabled(m.cleaning)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(m.selected.isEmpty ? L("s140") : L("s141", m.selected.count, bytes(m.pickedSize)))
                    .font(.subheadline.weight(.semibold))
                Text(m.hiddenSelection > 0 ? L("s142", m.hiddenSelection) : m.status)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if !m.notes.isEmpty {
                Button { m.showNotes = true } label: {
                    Label(L("s036", m.notes.count), systemImage: "exclamationmark.circle")
                }.font(.caption)
            }
            Button(L("s121")) { m.selected.formUnion(m.visible.map(\.id)) }
                .disabled(m.visible.isEmpty || m.busy || m.cleaning)
            if !m.selected.isEmpty {
                Button(L("s028")) { m.selected = [] }.disabled(m.cleaning)
            }
            Button { m.confirm = true } label: { Label(L("s037"), systemImage: "trash") }
                .primaryControl().disabled(m.selected.isEmpty || m.busy || m.cleaning)
        }
        .padding(17).glassPanel(radius: 18)
        .sheet(isPresented: $m.showNotes) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L("s036", m.notes.count)).font(.headline)
                    Spacer()
                    Button(L("s043")) { m.showNotes = false }.keyboardShortcut(.escape)
                }
                Divider()
                ScrollView {
                    Text(m.notes.joined(separator: "\n"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }.padding(24).frame(width: 520, height: min(420, CGFloat(130 + m.notes.count * 36)))
        }
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(L("s129")).font(.title2.weight(.semibold))
                    Spacer()
                    Button(L("s043")) { ui.showSettings = false }.keyboardShortcut(.escape)
                }
                VStack(alignment: .leading, spacing: 13) {
                    HStack { Text(L("s114")).font(.headline); Spacer(); Text(L("s115", m.enabled.count)).font(.caption).foregroundStyle(.secondary) }
                    ForEach(CleanupCategory.allCases) { category in
                        Toggle(isOn: Binding(
                            get: { m.enabled.contains(category) },
                            set: { m.setCategory(category, enabled: $0) }
                        )) {
                            Label(category.title, systemImage: category.symbol)
                        }.disabled(m.busy || m.cleaning)
                    }
                    if !m.excluded.isEmpty {
                        Button(L("s117", m.excluded.count)) { m.restoreExclusions() }
                            .font(.caption).disabled(m.busy || m.cleaning)
                    }
                }.padding(18).glassPanel(radius: 18)
                VStack(alignment: .leading, spacing: 13) {
                    Text(L("s061")).font(.headline)
                    Button { m.chooseFolder() } label: {
                        Label(displayPath(m.folder), systemImage: "folder").lineLimit(1).truncationMode(.middle)
                    }.help(m.folder.path)
                    Picker(L("s130"), selection: Binding(get: { m.threshold }, set: { m.threshold = $0; m.reset() })) {
                        Text(L("s131")).tag(Int64(50_000_000))
                        Text(L("s132")).tag(Int64(100_000_000))
                        Text(L("s133")).tag(Int64(500_000_000))
                        Text(L("s134")).tag(Int64(1_000_000_000))
                    }
                }.padding(18).glassPanel(radius: 18).disabled(m.busy || m.cleaning)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("MacTidy " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                                .font(.headline)
                            if let message = updater.message {
                                Text(message).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if updater.busy { ProgressView().controlSize(.small) }
                        Button(L("s157")) { Task { await updater.check() } }.disabled(updater.busy)
                    }
                }.padding(18).glassPanel(radius: 18)
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(L("s138"), isOn: Binding(
                        get: { m.weeklyEnabled },
                        set: { if $0 { m.weeklyConfirm = true } else { m.setWeekly(false) } }
                    )).disabled(m.weeklyBusy || m.cleaning)
                    Text(L("s139")).font(.caption).foregroundStyle(.secondary)
                    Text(m.weeklyResult).font(.caption).foregroundStyle(.secondary)
                }.padding(18).glassPanel(radius: 18)
            }.padding(24)
        }.frame(width: 540, height: 630)
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
        Window("MacTidy", id: "main") { LocalizedRoot(translates: true) { ContentView() } }.windowStyle(.hiddenTitleBar).defaultSize(width: 920, height: 690)
        Window(L("s164"), id: "storage") { LocalizedRoot(translates: false) { StorageView() } }.windowStyle(.hiddenTitleBar).defaultSize(width: 1000, height: 730)
        Window(L("s143"), id: "applications") { LocalizedRoot(translates: false) { ApplicationsView() } }.windowStyle(.hiddenTitleBar).defaultSize(width: 920, height: 690)
    }
}
#endif
