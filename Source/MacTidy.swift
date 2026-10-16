import SwiftUI
import AppKit
import QuartzCore

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
enum Brand {
    static let blue = Color.accentColor
    static let ring = AngularGradient(colors: [Color(red: 0.30, green: 0.69, blue: 1.0),
                                                Color(red: 0.30, green: 0.84, blue: 0.91),
                                                Color(red: 0.39, green: 0.52, blue: 0.98),
                                                Color(red: 0.30, green: 0.69, blue: 1.0)], center: .center)
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.86)
    static let telegram = URL(string: "https://t.me/R_3Design")!
}
// The command line toolchain has no SwiftUI macro plugin, so view state uses State values directly instead of @State.
struct GraphiteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { ProminentButton(configuration: configuration) }
}
private struct ProminentButton: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let hovering = State(initialValue: false)
    var body: some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .foregroundStyle(enabled ? Color.white : Color.secondary)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(enabled ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.08)), in: Capsule())
            .brightness(hovering.wrappedValue && !configuration.isPressed ? 0.05 : 0)
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : Brand.spring, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering.wrappedValue)
            .onHover { hovering.wrappedValue = enabled && $0 }
    }
}
/// A soft, static color wash keeps the window light without continuously redrawing large blurs.
struct AmbientBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Circle()
                    .fill(Color(red: 0.31, green: 0.68, blue: 1).opacity(0.20))
                    .frame(width: 340, height: 340).blur(radius: 85)
                    .position(x: geometry.size.width * 0.18, y: geometry.size.height * 0.17)
                Circle()
                    .fill(Color(red: 0.55, green: 0.48, blue: 0.96).opacity(0.14))
                    .frame(width: 330, height: 330).blur(radius: 90)
                    .position(x: geometry.size.width * 0.87, y: geometry.size.height * 0.84)
                Circle()
                    .fill(Color(red: 0.28, green: 0.82, blue: 0.82).opacity(0.12))
                    .frame(width: 220, height: 220).blur(radius: 75)
                    .position(x: geometry.size.width * 0.71, y: geometry.size.height * 0.23)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
/// Core Animation moves only a tiny layer, leaving SwiftUI's text and gauge idle.
private final class OrbitingDotView: NSView {
    private let orbit = CALayer()
    private let dot = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        dot.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
        dot.cornerRadius = 2.5
        dot.shadowColor = NSColor.systemBlue.cgColor
        dot.shadowOpacity = 0.65
        dot.shadowRadius = 7
        orbit.addSublayer(dot)
        layer?.addSublayer(orbit)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        orbit.bounds = bounds
        orbit.position = CGPoint(x: bounds.midX, y: bounds.midY)
        dot.frame = CGRect(x: bounds.midX - 2.5, y: bounds.midY + 95.5, width: 5, height: 5)
        CATransaction.commit()
    }

    func setActive(_ active: Bool) {
        if active && orbit.animation(forKey: "orbit") == nil {
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = 0
            animation.toValue = 2 * Double.pi
            animation.duration = 19
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            orbit.add(animation, forKey: "orbit")
        } else if !active {
            orbit.removeAnimation(forKey: "orbit")
        }
    }
}

private struct OrbitingDot: NSViewRepresentable {
    let active: Bool

    func makeNSView(context: Context) -> OrbitingDotView { OrbitingDotView(frame: NSRect(x: 0, y: 0, width: 200, height: 200)) }
    func updateNSView(_ view: OrbitingDotView, context: Context) { view.setActive(active) }
}

private struct RingAccents: View {
    let motionEnabled: Bool

    var body: some View {
        ZStack {
            OrbitingDot(active: motionEnabled).frame(width: 200, height: 200).allowsHitTesting(false)
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(Color(red: 0.45, green: 0.55, blue: 0.96).opacity(0.65))
                .offset(x: 118, y: -72)
            Circle()
                .fill(Color(red: 0.27, green: 0.80, blue: 0.83).opacity(0.55))
                .frame(width: 6, height: 6)
                .offset(x: -113, y: 65)
        }
        .accessibilityHidden(true)
    }
}

/// Free-space gauge in the style of macOS storage: the ring fills smoothly when it appears or the disk changes.
struct StorageRing: View {
    let used: Int64
    let total: Int64
    let available: Int64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private let shown = State(initialValue: 0.0)
    private var fraction: Double { total > 0 ? min(1, max(0, Double(used) / Double(total))) : 0 }
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.065), lineWidth: 13)
            Circle().trim(from: 0, to: shown.wrappedValue)
                .stroke(Brand.ring, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                .rotationEffect(.degrees(-90))
            RingAccents(motionEnabled: !reduceMotion && scenePhase == .active)
            VStack(spacing: 3) {
                Text(bytes(available)).font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(L("s108", bytes(total))).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineLimit(2)
            }.padding(.horizontal, 26)
        }
        .frame(width: 200, height: 200)
        .onAppear {
            if reduceMotion { shown.wrappedValue = fraction }
            else { withAnimation(.easeOut(duration: 1.0).delay(0.15)) { shown.wrappedValue = fraction } }
        }
        .onChange(of: fraction) { value in
            if reduceMotion { shown.wrappedValue = value }
            else { withAnimation(.easeInOut(duration: 0.6)) { shown.wrappedValue = value } }
        }
        .accessibilityElement(children: .combine)
    }
}
private struct NavigationPill: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    private let hovering = State(initialValue: false)

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 18).frame(height: 38)
                .background(selected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(hovering.wrappedValue ? 0.05 : 0),
                            in: Capsule())
                .overlay(Capsule().stroke(selected ? Color.accentColor.opacity(0.16) : Color.clear, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering.wrappedValue = $0 }
        .animation(.easeOut(duration: 0.18), value: selected)
        .animation(.easeOut(duration: 0.18), value: hovering.wrappedValue)
    }
}
/// Rounded tinted square with an SF Symbol, like the icons in System Settings.
struct SymbolTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}
struct SupportCard: View {
    var body: some View {
        HStack(spacing: 14) {
            SymbolTile(symbol: "heart.fill", color: .pink)
            VStack(alignment: .leading, spacing: 3) {
                Text(L("s312")).font(.headline)
                Text(L("s313")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Link(destination: Brand.telegram) { Label("@R_3Design", systemImage: "paperplane.fill") }
                .buttonStyle(GraphiteButtonStyle()).help(L("s314")).accessibilityLabel(L("s314"))
        }
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
    @Published var search = ""
    @Published var sort = ResultSort.size
    @Published var status = L("s089")
    @Published var error: String?
    @Published var confirm = false
    @Published var capacity = DiskCapacity(total: 0, immediateFree: 0, available: 0)
    @Published var excluded = Set(UserDefaults.standard.stringArray(forKey: "excludedPaths") ?? [])
    @Published var weeklyEnabled = WeeklySchedule.enabled
    @Published var cleanupCadence = WeeklySchedule.cadence
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
        if let current = DiskCapacity.current() { capacity = current }
    }
    func reset() {
        guard !cleaning else { return }
        cancel(); candidates = []; selected = []; focused = nil; completed = []; hasScanned = false
        search = ""; category = nil; error = nil; status = L("s090")
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
                candidates = result.candidates; completed = result.completed; hasScanned = true
                status = L("s094" , candidates.count)
                if result.unavailableChosenFolder { error = L("s002", displayPath(config.folder)) }
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
        let cadence = cleanupCadence
        Task {
            do {
                try await Task.detached { if enabled { try WeeklySchedule.enable(helper: helper, cadence: cadence) } else { try WeeklySchedule.disable() } }.value
            } catch { self.error = error.localizedDescription }
            weeklyEnabled = WeeklySchedule.enabled; cleanupCadence = WeeklySchedule.cadence; weeklyBusy = false; weeklyResult = WeeklySchedule.lastResult()
        }
    }
    func setCleanupCadence(_ cadence: CleanupCadence) {
        guard !weeklyBusy else { return }
        cleanupCadence = cadence
        WeeklySchedule.cadence = cadence
        if weeklyEnabled { setWeekly(true) }
    }
}
@MainActor final class CleanupUIState: ObservableObject {
    @Published var showSettings = false
    @Published var showPermissions = false
    @Published var showCategories = false
    @Published var showSupport = false
    @Published var page: MacSpacePage = .cleanup
}
enum MacSpacePage: Hashable { case cleanup, applications, antivirus }
extension Notification.Name { static let showApplications = Notification.Name("MacSpaceShowApplications") }
/// Other windows open app review through this: it brings the main window forward on its Applications tab.
@MainActor enum ApplicationsRoute {
    static var pending = false
    static func show(_ openWindow: OpenWindowAction) {
        pending = true
        openWindow(id: "main")
        NotificationCenter.default.post(name: .showApplications, object: nil)
    }
}
struct ContentView: View {
    @StateObject private var m = Model()
    @StateObject private var ui = CleanupUIState()
    @StateObject private var updater = UpdateModel()
    @StateObject private var antivirus = AntivirusModel()
    @StateObject private var applications = ApplicationsModel()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 22) {
            header
            pagePicker
            if updater.available != nil { updateBanner }
            Group {
                if ui.page == .antivirus { AntivirusView(model: antivirus).transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing))) }
                else if ui.page == .applications { ApplicationsView(m: applications).transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96))) }
                else if !m.hasScanned && !m.busy { welcome.transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))) }
                else { review.transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))) }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.15) : Brand.spring, value: ui.page)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : Brand.spring, value: m.hasScanned || m.busy)
        }
        .padding(28)
        .frame(minWidth: 760, minHeight: 620)
        .background { AmbientBackdrop().ignoresSafeArea() }
        .tint(Brand.blue)
        .sheet(isPresented: $ui.showSettings) { settings }
        .sheet(isPresented: $ui.showSupport) { supportSheet }
        .sheet(isPresented: $ui.showPermissions) { PermissionGuideView() }
        .task { await updater.check(automatic: true) }
        .task { await antivirus.maintainDefinitions() }
        .task {
            let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LoginItems/MacTidyHelper.app")
            do { try await Task.detached { try WeeklySchedule.updateHelperIfNeeded(helper: helper) }.value }
            catch { m.error = error.localizedDescription }
            m.weeklyEnabled = WeeklySchedule.enabled
            m.weeklyResult = WeeklySchedule.lastResult()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MacTidyLanguageUpdated"))) { _ in
            m.objectWillChange.send(); applications.objectWillChange.send()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showApplications)) { _ in
            ApplicationsRoute.pending = false; ui.page = .applications
        }
        .onAppear { if ApplicationsRoute.pending { ApplicationsRoute.pending = false; ui.page = .applications } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            m.weeklyEnabled = WeeklySchedule.enabled; m.cleanupCadence = WeeklySchedule.cadence; m.weeklyResult = WeeklySchedule.lastResult(); m.refreshDisk()
        }
        .onChange(of: m.weeklyEnabled) { enabled in
            if enabled && !UserDefaults.standard.bool(forKey: "weeklyAccessGuideSeen-v1") {
                UserDefaults.standard.set(true, forKey: "weeklyAccessGuideSeen-v1")
                ui.showPermissions = true
            }
        }
        .alert(L("s099"), isPresented: $m.weeklyConfirm) {
            Button(L("s039"), role: .cancel) {}
            Button(L("s100")) { m.setWeekly(true) }
        } message: { Text(L("s101", m.cleanupCadence.title)) }
        .alert(L("s102"), isPresented: $m.confirm) {
            Button(L("s039"), role: .cancel) {}
            Button(L("s040"), role: .destructive) { m.trash() }
        } message: { Text(L("s103", m.selected.count, bytes(m.pickedSize), m.hiddenSelection)) }
        .alert(L("s042"), isPresented: Binding(get: { m.error != nil }, set: { if !$0 { m.error = nil } })) {
            Button(L("s043")) { m.error = nil }
        } message: { Text(m.error ?? "") }
    }

    private var pagePicker: some View {
        HStack(spacing: 4) {
            NavigationPill(title: L("s256"), symbol: "sparkles", selected: ui.page == .cleanup) { ui.page = .cleanup }
            NavigationPill(title: L("s014"), symbol: "square.grid.2x2", selected: ui.page == .applications) { ui.page = .applications }
            NavigationPill(title: L("s255"), symbol: "shield.lefthalf.filled", selected: ui.page == .antivirus) { ui.page = .antivirus }
        }
        .padding(4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.06)))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: Bundle.main.url(forResource: "MacSpaceIcon", withExtension: "icns")
                .flatMap { NSImage(contentsOf: $0) } ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable().frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("MacSpace").font(.system(size: 23, weight: .semibold, design: .rounded))
                Text(L("s104")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { openWindow(id: "storage") } label: {
                Label(L("s164"), systemImage: "internaldrive")
            }.buttonStyle(.bordered).help(L("s164"))
            Menu {
                Button(L("s129"), systemImage: "slider.horizontal.3") { ui.showSettings = true }
                Divider()
                Button(L("s312"), systemImage: "heart") { ui.showSupport = true }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 18)).frame(width: 30, height: 30)
            }.menuStyle(.borderlessButton).fixedSize().help(L("s252")).accessibilityLabel(L("s252"))
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
        VStack(spacing: 12) {
            StorageRing(used: m.capacity.used, total: m.capacity.total, available: m.capacity.available)
            Text(L("s107")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            if m.capacity.reclaimable > 0 {
                Text(L("s253", bytes(m.capacity.reclaimable)))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 0) {
                    Label(L("s256"), systemImage: "sparkles")
                        .font(.caption.weight(.semibold)).foregroundStyle(Brand.blue)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(Brand.blue.opacity(0.09), in: Capsule())
                    Text(L("s124"))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .padding(.top, 24)
                    Text(L("s113"))
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                    Button { m.scan() } label: {
                        Label(L("s106"), systemImage: "sparkle.magnifyingglass")
                            .padding(.horizontal, 14).padding(.vertical, 5)
                    }
                    .buttonStyle(GraphiteButtonStyle()).controlSize(.large)
                    .disabled(m.enabled.isEmpty)
                    .keyboardShortcut("r", modifiers: .command)
                    .padding(.top, 28)
                    Button { ui.showSupport = true } label: {
                        Label(L("s312"), systemImage: "heart.fill").font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .padding(.top, 18)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                diskSummary.frame(width: 240)
            }
            .padding(.horizontal, 46).padding(.vertical, 28)
            .frame(maxWidth: .infinity)
            .frame(height: 350)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(Color.primary.opacity(0.07)))
            .shadow(color: .black.opacity(0.055), radius: 22, y: 10)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            ForEach(CleanupCategory.allCases) { category in
                                Button(category.title) { m.category = category }
                            }
                            Divider()
                            Menu(L("s120")) {
                                ForEach(ResultSort.allCases, id: \.self) { sort in
                                    Button(sort.title) { m.sort = sort }
                                }
                            }
                        } label: {
                            Label(m.category?.title ?? L("s116"), systemImage: "line.3.horizontal.decrease")
                        }.menuStyle(.borderlessButton).fixedSize().help(L("s114"))
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
                .font(.system(size: 20)).foregroundStyle(Brand.blue).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.entry.url.lastPathComponent).font(.callout.weight(.medium)).lineLimit(1)
                Text(displayPath(item.entry.url.deletingLastPathComponent())).font(.caption)
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 5)
            Text(bytes(item.entry.size)).font(.callout.weight(.semibold)).monospacedDigit()
        }
        .padding(11).contentShape(Rectangle())
        .background(m.focused == item.id ? Brand.blue.opacity(0.16) :
                    (m.selected.contains(item.id) ? Brand.blue.opacity(0.07) : .clear),
                    in: RoundedRectangle(cornerRadius: 11))
        .animation(.easeOut(duration: 0.15), value: m.selected.contains(item.id))
        .animation(.easeOut(duration: 0.15), value: m.focused)
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
                if m.hiddenSelection > 0 {
                    Text(L("s142", m.hiddenSelection))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Button(L("s121")) { m.selected.formUnion(m.visible.map(\.id)) }
                .disabled(m.visible.isEmpty || m.busy || m.cleaning)
            if !m.selected.isEmpty {
                Button(L("s028")) { m.selected = [] }.disabled(m.cleaning)
            }
            Button { m.confirm = true } label: { Label(L("s037"), systemImage: "trash") }
                .primaryControl().disabled(m.selected.isEmpty || m.busy || m.cleaning)
        }
        .padding(17).glassPanel(radius: 18)
    }

    private var supportSheet: some View {
        VStack(spacing: 16) {
            SymbolTile(symbol: "heart.fill", color: .pink, size: 64)
            Text(L("s315")).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            Text(L("s313")).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: Brand.telegram) {
                Label(L("s314") + " · @R_3Design", systemImage: "paperplane.fill").padding(.vertical, 2)
            }.buttonStyle(GraphiteButtonStyle()).padding(.top, 4)
            Button(L("s197")) { ui.showSupport = false }.buttonStyle(.borderless).keyboardShortcut(.escape)
        }
        .padding(32).frame(width: 400)
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(L("s129")).font(.title2.weight(.semibold))
                    Spacer()
                    Button {
                        ui.showSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { ui.showPermissions = true }
                    } label: {
                        Image(systemName: "lock.shield").frame(width: 22, height: 22)
                    }.buttonStyle(.plain).help(L("s218")).accessibilityLabel(L("s218"))
                    Button { ui.showSettings = false } label: {
                        Image(systemName: "xmark").frame(width: 22, height: 22)
                    }.buttonStyle(.plain).help(L("s197")).accessibilityLabel(L("s197")).keyboardShortcut(.escape)
                }
                DisclosureGroup(isExpanded: $ui.showCategories) {
                    VStack(alignment: .leading, spacing: 13) {
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
                    }.padding(.top, 12)
                } label: {
                    HStack { Text(L("s114")).font(.headline); Spacer(); Text(L("s115", m.enabled.count)).font(.caption).foregroundStyle(.secondary) }
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
                            Text("MacSpace " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
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
                    HStack {
                        Text(L("s286"))
                        Spacer()
                        Picker(L("s286"), selection: Binding(get: { m.cleanupCadence }, set: { m.setCleanupCadence($0) })) {
                            ForEach(CleanupCadence.allCases) { cadence in Text(cadence.title).tag(cadence) }
                        }.labelsHidden().frame(width: 160).disabled(m.weeklyBusy || m.cleaning)
                    }
                    Text(L("s139")).font(.caption).foregroundStyle(.secondary)
                    Text(m.weeklyResult).font(.caption).foregroundStyle(.secondary)
                }.padding(18).glassPanel(radius: 18)
                SupportCard().padding(18).glassPanel(radius: 18)
            }.padding(24)
        }.frame(width: 540, height: 630)
    }
}
#if !TESTING
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "MacSpaceIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = icon
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        AntivirusEngine.cancelActiveScan()
    }
}
@main struct MacTidy: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Window("MacSpace", id: "main") { LocalizedRoot(translates: true) { ContentView() } }.windowStyle(.hiddenTitleBar).defaultSize(width: 920, height: 690)
        Window(L("s164"), id: "storage") { LocalizedRoot(translates: false) { StorageView() } }.windowStyle(.hiddenTitleBar).defaultSize(width: 1000, height: 730)
    }
}
#endif
