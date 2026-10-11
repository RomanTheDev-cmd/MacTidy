import SwiftUI
import AppKit

struct ShieldBadge: View {
    enum Mode { case idle, scanning, threat }
    let state: Mode
    private let pulse = State(initialValue: false)
    var body: some View {
        let color: Color = state == .threat ? .orange : .accentColor
        ZStack {
            if state == .scanning {
                Circle().stroke(color.opacity(0.4), lineWidth: 1.5)
                    .scaleEffect(pulse.wrappedValue ? 1.5 : 1).opacity(pulse.wrappedValue ? 0 : 1)
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse.wrappedValue)
            }
            Circle().fill(color.opacity(0.13))
            Image(systemName: state == .threat ? "exclamationmark.shield.fill" : (state == .scanning ? "magnifyingglass" : "checkmark.shield.fill"))
                .font(.system(size: 30, weight: .medium)).foregroundStyle(color)
        }
        .frame(width: 68, height: 68)
        .animation(Brand.spring, value: state)
        .onAppear { pulse.wrappedValue = true }
    }
}

struct AntivirusView: View {
    @ObservedObject var model: AntivirusModel

    var body: some View {
        ScrollView {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                ShieldBadge(state: !model.findings.isEmpty ? .threat : (model.scanning ? .scanning : .idle))
                Text(L("s255")).font(.system(size: 25, weight: .semibold, design: .rounded))
                Text(L("s265")).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: 540)
                HStack(spacing: 7) {
                    if model.updating || model.scanning { ProgressView().controlSize(.small) }
                    Text(model.status).font(.callout.weight(.medium))
                }.padding(.top, 2)
                if model.scanning { scanProgress }
                if let updated = model.lastUpdated {
                    Text(L("s266", DateFormatter.localizedString(from: updated, dateStyle: .medium, timeStyle: .short)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.error != nil {
                    Text(model.error ?? "").font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                        .frame(maxWidth: 620)
                }
                HStack(spacing: 12) {
                    Button { model.scan() } label: {
                        Label(model.scanning ? L("s267") : L("s268"), systemImage: "magnifyingglass")
                            .frame(minWidth: 205).padding(.vertical, 4)
                    }.buttonStyle(GraphiteButtonStyle()).controlSize(.large)
                        .disabled(!model.ready || model.updating || model.scanning)
                    if model.scanning {
                        Button(model.stopping ? L("s299") : L("s298")) { model.stopScan() }
                            .buttonStyle(.bordered).disabled(model.stopping)
                    }
                    Button { PermissionGuide.openFullDiskAccess() } label: {
                        Image(systemName: "lock.shield")
                    }
                    .buttonStyle(.bordered).controlSize(.small).fixedSize()
                    .help(L("s269")).accessibilityLabel(L("s269"))
                }
                if model.error != nil && !model.updating {
                    Button(L("s275")) { Task { await model.updateDefinitions() } }
                        .buttonStyle(.borderless).font(.caption).disabled(model.scanning)
                }
                Text(L("s270")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: 620)
                Link(L("s274"), destination: URL(string: "https://github.com/Cisco-Talos/clamav/releases/tag/clamav-\(AntivirusEngine.release)")!)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .glassPanel(radius: 24)

            Surface {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(L("s271")).font(.headline)
                        Spacer()
                        if !model.findings.isEmpty { Text(L("s263", model.findings.count)).font(.caption).foregroundStyle(.secondary) }
                    }.padding(16)
                    Divider()
                    if model.findings.isEmpty {
                        Text(model.scanning ? L("s272") : L("s273"))
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(25)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 3) {
                                ForEach(model.findings) { finding in
                                    HStack(spacing: 12) {
                                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(finding.signature).font(.callout.weight(.semibold)).lineLimit(1)
                                            Text(finding.path).font(.caption).foregroundStyle(.secondary)
                                                .lineLimit(1).truncationMode(.middle)
                                        }
                                        Spacer()
                                        Button(L("s048")) {
                                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: finding.path)])
                                        }.font(.caption)
                                        if finding.removable {
                                            Button { model.requestRemoval(finding) } label: {
                                                Image(systemName: "trash")
                                            }
                                            .buttonStyle(.borderless)
                                            .help(L("s283"))
                                            .accessibilityLabel(L("s283"))
                                        } else {
                                            Image(systemName: "lock.fill").foregroundStyle(.tertiary)
                                                .help(L("s290"))
                                        }
                                    }.padding(11)
                                }
                            }.padding(7)
                        }.frame(maxHeight: 260)
                    }
                }.frame(maxWidth: .infinity)
            }
            .frame(minHeight: 180)
            historyPanel
        }
        .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(L("s281"), isPresented: Binding(
            get: { model.pendingRemoval != nil },
            set: { if !$0 { model.pendingRemoval = nil } }
        ), titleVisibility: .visible) {
            Button(L("s283"), role: .destructive) { model.confirmRemoval() }
            Button(L("s039"), role: .cancel) { model.pendingRemoval = nil }
        } message: {
            Text(L("s282", model.pendingRemoval.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? ""))
        }
    }

    private var scanProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.scanPhase == .counting {
                ProgressView()
                Text(L("s291")).font(.caption.weight(.medium))
                Text(L("s292", model.countedFiles)).font(.caption).foregroundStyle(.secondary)
            } else {
                if model.estimatedFiles > 0 {
                    ProgressView(value: min(0.98, Double(model.scannedFiles) / Double(model.estimatedFiles)))
                } else { ProgressView() }
                Text(model.estimatedFiles > 0
                     ? L("s293", model.scannedFiles, model.estimatedFiles)
                     : L("s294", model.scannedFiles))
                    .font(.caption.weight(.medium))
                if !model.findings.isEmpty {
                    Text(L("s307", model.findings.count)).font(.caption).foregroundStyle(.orange)
                }
            }
            HStack {
                Text(L("s295", duration(model.elapsedSeconds)))
                Spacer()
                if model.scanPhase == .scanning,
                   let remaining = AntivirusScanProgress.estimatedSecondsRemaining(
                    scanned: model.scannedFiles, total: model.estimatedFiles, elapsed: model.elapsedSeconds) {
                    Text(L("s296", duration(remaining)))
                } else { Text(L("s297")) }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: 590)
        .padding(.vertical, 8)
    }

    private var historyPanel: some View {
        Surface {
            DisclosureGroup(isExpanded: $model.historyExpanded) {
                if model.history.isEmpty {
                    Text(L("s309")).font(.caption).foregroundStyle(.secondary).padding(.top, 12)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.history) { record in
                            DisclosureGroup {
                                if record.findings.isEmpty {
                                    Text(L("s310")).font(.caption).foregroundStyle(.secondary)
                                } else {
                                    ForEach(record.findings, id: \.self) { finding in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(finding.signature).font(.caption.weight(.medium))
                                            Text(finding.path).font(.caption2).foregroundStyle(.secondary)
                                                .lineLimit(2).truncationMode(.middle)
                                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(DateFormatter.localizedString(from: record.startedAt, dateStyle: .medium, timeStyle: .short))
                                        .font(.callout.weight(.medium))
                                    Text(L("s302", record.scannedFiles, record.findings.count,
                                           duration(record.finishedAt.timeIntervalSince(record.startedAt))) + " · " + outcomeTitle(record.outcome))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if record.id != model.history.last?.id { Divider() }
                        }
                    }.padding(.top, 12)
                }
            } label: {
                HStack {
                    Text(L("s301")).font(.headline)
                    Spacer()
                    if let latest = model.history.first {
                        Text(DateFormatter.localizedString(from: latest.startedAt, dateStyle: .short, timeStyle: .none))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
        }
    }

    private func outcomeTitle(_ outcome: AntivirusScanRecord.Outcome) -> String {
        switch outcome {
        case .finished: return L("s303")
        case .stopped: return L("s304")
        case .partial: return L("s305")
        case .failed: return L("s306")
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: max(0, seconds)) ?? "0"
    }
}
