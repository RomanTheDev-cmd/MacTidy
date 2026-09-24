import Foundation
import CryptoKit
import AppKit
import SwiftUI

struct AppVersion: Comparable, Equatable {
    let parts: [Int]
    init?(_ value: String) {
        let source = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let strings = source.split(separator: ".", omittingEmptySubsequences: false)
        guard strings.count == 3,
              strings.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let numbers = strings.compactMap { Int($0) }
        guard numbers.count == 3, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        parts = numbers
    }
    static func < (a: Self, b: Self) -> Bool {
        for (x, y) in zip(a.parts, b.parts) where x != y { return x < y }
        return false
    }
    var description: String { parts.map(String.init).joined(separator: ".") }
}

struct ReleaseAsset: Decodable {
    let name: String
    let size: Int
    let digest: String?
    let browser_download_url: URL

    var expectedHash: String? {
        guard let digest, digest.hasPrefix("sha256:") else { return nil }
        let hex = String(digest.dropFirst(7))
        return hex.count == 64 && hex.allSatisfy({ $0.isHexDigit }) ? hex.lowercased() : nil
    }
    func validatedURL(tag: String) -> URL? {
        guard browser_download_url.scheme == "https", browser_download_url.host == "github.com",
              browser_download_url.path == "/RomanTheDev-cmd/MacTidy/releases/download/\(tag)/\(name)",
              browser_download_url.query == nil, browser_download_url.fragment == nil else { return nil }
        return browser_download_url
    }
}
struct GitHubRelease: Decodable {
    let tag_name: String
    let draft: Bool
    let prerelease: Bool
    let assets: [ReleaseAsset]
}
struct AvailableUpdate {
    let version: AppVersion
    let tag: String
    let package: ReleaseAsset
    let signature: ReleaseAsset

    static func parse(_ data: Data, current: AppVersion, architecture: String = "arm64") throws -> Self? {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.draft && !release.prerelease,
              release.tag_name.hasPrefix("v"),
              let version = AppVersion(release.tag_name),
              version > current else { return nil }
        guard release.tag_name == "v" + version.description else { throw UpdateError.invalidRelease }
        let packageName = "MacTidy-\(version.description)-\(architecture).pkg"
        guard let package = release.assets.first(where: { $0.name == packageName }),
              let signature = release.assets.first(where: { $0.name == packageName + ".sig" }),
              package.size > 100_000 && package.size < 150_000_000,
              signature.size == 64,
              package.expectedHash != nil, signature.expectedHash != nil,
              package.validatedURL(tag: release.tag_name) != nil,
              signature.validatedURL(tag: release.tag_name) != nil else { throw UpdateError.invalidRelease }
        return Self(version: version, tag: release.tag_name, package: package, signature: signature)
    }
}

enum UpdateError: LocalizedError {
    case invalidRelease, badResponse, badDownload, badSignature, installerFailed
    var errorDescription: String? {
        switch self {
        case .invalidRelease: return "The GitHub release is missing a valid signed installer."
        case .badResponse: return "GitHub did not return a valid response."
        case .badDownload: return "The downloaded installer failed its SHA-256 check."
        case .badSignature: return "The installer signature is invalid."
        case .installerFailed: return "macOS could not open the installer."
        }
    }
}

enum UpdateVerifier {
    static let officialPublicKey = Data(base64Encoded: "DNLuaMjniKfU9XFZPX4HEu+uAabqKggUzHzZWSjnnO8=")!
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func verify(package: Data, signature: Data, publicKey: Data = officialPublicKey) -> Bool {
        guard signature.count == 64,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else { return false }
        return key.isValidSignature(signature, for: package)
    }
}

@MainActor final class UpdateModel: ObservableObject {
    @Published private(set) var available: AvailableUpdate?
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    private var checked = false
    private let endpoint = URL(string: "https://api.github.com/repos/RomanTheDev-cmd/MacTidy/releases/latest")!

    func check(automatic: Bool = false) async {
        guard !busy, !automatic || !checked else { return }
        checked = true; busy = true
        if !automatic { message = L("s151") }
        defer { busy = false }
        do {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 15
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("MacTidy-updater", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 2_000_000 else { throw UpdateError.badResponse }
            guard let current = AppVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") else { throw UpdateError.invalidRelease }
            #if arch(arm64)
            let architecture = "arm64"
            #else
            let architecture = "x86_64"
            #endif
            available = try AvailableUpdate.parse(data, current: current, architecture: architecture)
            if let available {
                message = L("s152", available.version.description)
                if automatic && UserDefaults.standard.string(forKey: "autoOpenedUpdateVersion") != available.version.description {
                    busy = false
                    await install()
                }
            } else { message = automatic ? nil : L("s156") }
        } catch { message = L("s158", error.localizedDescription) }
    }

    func install() async {
        guard let available, !busy else { return }
        busy = true; message = L("s153")
        defer { busy = false }
        do {
            let packageURL = try await verifiedPackage(for: available)
            guard NSWorkspace.shared.open(packageURL) else { throw UpdateError.installerFailed }
            UserDefaults.standard.set(available.version.description, forKey: "autoOpenedUpdateVersion")
            message = L("s155")
        } catch { message = L("s158", error.localizedDescription) }
    }

    private func verifiedPackage(for release: AvailableUpdate) async throws -> URL {
        let package = try await download(release.package, tag: release.tag)
        let signature = try await download(release.signature, tag: release.tag)
        guard UpdateVerifier.verify(package: package, signature: signature) else { throw UpdateError.badSignature }
        let updates = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacTidy/Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: updates, withIntermediateDirectories: true)
        let destination = updates.appendingPathComponent(release.package.name)
        try package.write(to: destination, options: .atomic)
        // Recheck the on-disk file immediately before handing it to Installer.
        guard UpdateVerifier.verify(package: try Data(contentsOf: destination), signature: signature) else {
            try? FileManager.default.removeItem(at: destination)
            throw UpdateError.badSignature
        }
        return destination
    }

    private func download(_ asset: ReleaseAsset, tag: String) async throws -> Data {
        guard let url = asset.validatedURL(tag: tag), let hash = asset.expectedHash else { throw UpdateError.invalidRelease }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("MacTidy-updater", forHTTPHeaderField: "User-Agent")
        let (file, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw UpdateError.badResponse }
        let data = try Data(contentsOf: file)
        guard data.count == asset.size, UpdateVerifier.hash(data) == hash else { throw UpdateError.badDownload }
        return data
    }
}
