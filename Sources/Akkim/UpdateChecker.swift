// Portions of this file are derived from ChargeWatching
// (https://github.com/TY-teo/ChargeWatching), MIT License,
// Copyright (c) 2026 TY-teo. See LICENSE and THIRD-PARTY-NOTICES.md.

import Foundation
import AppKit
import CryptoKit
import Security

/// Checks GitHub Releases for a newer build and installs it in place.
///
/// The release workflow attaches `Akkim.zip` + `Akkim.zip.sha256` to every tag,
/// and `releases/latest` always redirects to the newest tag — so a version check
/// is one HTTP request with no API token and no rate limit.
@MainActor
final class UpdateChecker: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case downloading
        case verifying
        case installing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// Newest version seen by a successful check; survives relaunches.
    @Published private(set) var latestVersion: String?

    static let repoSlug = "karanglass24-lang/akkim"
    static var latestURL: URL {
        URL(string: "https://github.com/\(repoSlug)/releases/latest")!
    }
    static var zipURL: URL {
        URL(string: "https://github.com/\(repoSlug)/releases/latest/download/Akkim.zip")!
    }
    static var shaURL: URL {
        URL(string: "https://github.com/\(repoSlug)/releases/latest/download/Akkim.zip.sha256")!
    }

    static var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }

    private var defaults: UserDefaults { .standard }
    private var lastCheck: Date {
        get { defaults.object(forKey: "updateLastCheck") as? Date ?? .distantPast }
        set { defaults.set(newValue, forKey: "updateLastCheck") }
    }

    /// Version shown in the UI when it is newer than the running build.
    var availableVersion: String? {
        guard let latestVersion, Self.isNewer(latestVersion, than: Self.currentVersion) else { return nil }
        return latestVersion
    }

    var isUpdateAvailable: Bool { availableVersion != nil }

    /// A copy we can replace (the user installed it somewhere writable).
    var canReplaceInPlace: Bool {
        FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.path)
    }

    init() {
        latestVersion = defaults.string(forKey: "updateLatestVersion")
    }

    // MARK: - Check

    /// Launch-time check: at most one request every 12 hours.
    func checkOnLaunch() {
        guard Date().timeIntervalSince(lastCheck) > 12 * 3600 else { return }
        Task { await check() }
    }

    func check() async {
        phase = .checking
        var request = URLRequest(url: Self.latestURL)
        request.timeoutInterval = 15
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
                phase = .failed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return
            }
            // `/releases/latest` redirects to `…/releases/tag/v1.6.1`.
            guard let tag = http.url?.lastPathComponent, tag.hasPrefix("v") else {
                phase = .failed("release tag")
                return
            }
            let version = String(tag.dropFirst())
            lastCheck = Date()

            if Self.isNewer(version, than: Self.currentVersion) {
                latestVersion = version
                defaults.set(version, forKey: "updateLatestVersion")
                phase = .available(version)
            } else {
                latestVersion = nil
                defaults.removeObject(forKey: "updateLatestVersion")
                phase = .upToDate
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Install

    /// Downloads, checksums, unpacks and swaps the running app, then relaunches.
    func install() async {
        phase = .downloading
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("akkim-update", isDirectory: true)
        do {
            try? FileManager.default.removeItem(at: work)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

            let zip = try await download(Self.zipURL, to: work.appendingPathComponent("Akkim.zip"))
            let sha = try await download(Self.shaURL, to: work.appendingPathComponent("Akkim.zip.sha256"))

            phase = .verifying
            try verify(zip: zip, against: sha)

            phase = .installing
            let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
            try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
            let newApp = unpacked.appendingPathComponent("Akkim.app")
            guard FileManager.default.fileExists(atPath: newApp.path) else {
                throw UpdateError.missingAppBundle
            }
            try verifySigner(of: newApp)
            try swapAndRelaunch(newApp: newApp, work: work)
            NSApp.terminate(nil)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func download(_ url: URL, to destination: URL) async throws -> URL {
        let (temp, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            throw UpdateError.http(http.statusCode)
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
        return destination
    }

    /// The release workflow publishes `shasum -a 256 Akkim.zip`.
    private func verify(zip: URL, against shaFile: URL) throws {
        let text = try String(contentsOf: shaFile, encoding: .utf8)
        guard let expected = text.split(separator: " ").first?.lowercased(),
              expected.count == 64 else {
            throw UpdateError.badChecksumFile
        }
        let digest = SHA256.hash(data: try Data(contentsOf: zip))
        let actual = digest.map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw UpdateError.checksumMismatch }
    }

    /// The checksum is published next to the zip, so it only proves integrity.
    /// Once releases are Developer ID signed, the Team ID proves who built them:
    /// a signed app only accepts an update from the same team. Ad-hoc builds
    /// have no team, so the check is skipped for them.
    private func verifySigner(of newApp: URL) throws {
        guard let expected = Self.teamIdentifier(of: Bundle.main.bundleURL) else { return }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(newApp as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess,
              Self.teamIdentifier(of: newApp) == expected else {
            throw UpdateError.signerMismatch
        }
    }

    private static func teamIdentifier(of bundle: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Waits for this process to exit, replaces the bundle, relaunches.
    private func swapAndRelaunch(newApp: URL, work: URL) throws {
        let destination = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: destination.path) else {
            throw UpdateError.notWritable
        }

        // Both paths are quoted inside the script, so spaces are safe.
        let script = """
        #!/bin/sh
        PID=\(ProcessInfo.processInfo.processIdentifier)
        while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
        sleep 0.5
        DST="\(destination.path)"
        SRC="\(newApp.path)"
        OLD="$DST.replaced"
        rm -rf "$OLD"
        if ! mv "$DST" "$OLD"; then /usr/bin/open "$DST"; exit 1; fi
        if ! mv "$SRC" "$DST"; then mv "$OLD" "$DST"; /usr/bin/open "$DST"; exit 1; fi
        rm -rf "$OLD"
        /usr/bin/open "$DST"
        """
        let scriptURL = work.appendingPathComponent("swap.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private func run(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.unzipFailed(process.terminationStatus)
        }
    }

    /// Numeric "1.10.0" > "1.9.9" style comparison.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let right = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}

enum UpdateError: LocalizedError {
    case http(Int)
    case badChecksumFile
    case checksumMismatch
    case missingAppBundle
    case unzipFailed(Int32)
    case notWritable
    case signerMismatch

    var errorDescription: String? {
        switch self {
        case .http(let code): return "HTTP \(code)"
        case .badChecksumFile: return L10n.t(.errUpdateChecksumFile)
        case .checksumMismatch: return L10n.t(.errUpdateChecksum)
        case .missingAppBundle: return L10n.t(.errUpdateNoBundle)
        case .unzipFailed(let status): return "unzip (\(status))"
        case .notWritable: return L10n.t(.updateNeedsManual)
        case .signerMismatch: return L10n.t(.errUpdateSigner)
        }
    }
}
