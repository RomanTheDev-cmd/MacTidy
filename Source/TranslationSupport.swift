import SwiftUI
import Translation

struct LocalizedRoot<Content: View>: View {
    let translates: Bool
    @ViewBuilder var content: () -> Content
    var body: some View {
        Group {
            if #available(macOS 15.0, *), translates {
                TranslationHost(content: content)
            } else { content() }
        }
        .environment(\.layoutDirection, Locale.Language(identifier: AppLocalization.shared.language).characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
        .environment(\.locale, Locale(identifier: AppLocalization.shared.language))
    }
}
@available(macOS 15.0, *)
@MainActor private final class TranslationModel: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?
}
@available(macOS 15.0, *)
private struct TranslationHost<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @StateObject private var model = TranslationModel()
    var body: some View {
        content()
            .task {
                let localization = AppLocalization.shared
                guard localization.needsTranslation else { return }
                let source = Locale.Language(identifier: "en")
                let target = Locale.Language(identifier: localization.language)
                guard await LanguageAvailability().status(from: source, to: target) != .unsupported else { return }
                model.configuration = .init(source: source, target: target)
            }
            .translationTask(model.configuration) { session in
                do {
                    try await session.prepareTranslation()
                    let requests = AppLocalization.shared.english.sorted { $0.key < $1.key }.map { TranslationSession.Request(sourceText: $0.value, clientIdentifier: $0.key) }
                    let responses = try await session.translations(from: requests)
                    var catalog: [String: String] = [:]
                    for response in responses { if let key = response.clientIdentifier { catalog[key] = response.targetText } }
                    try AppLocalization.shared.install(catalog)
                    NotificationCenter.default.post(name: .init("MacTidyLanguageUpdated"), object: nil)
                } catch { /* Keep the complete English interface if translation is unavailable or declined. */ }
            }
    }
}
