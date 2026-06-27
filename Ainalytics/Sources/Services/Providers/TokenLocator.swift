import Foundation
import Security

/// Locates a provider's CLI credential **without reading its value**.
///
/// Read-only by contract (PROJECT-SPEC §6, ARCHITECTURE §10): it reports only
/// whether a credential is present and locatable. It never returns, logs, or
/// persists the token contents, and never writes to any credential store.
enum TokenLocator {

    /// Whether a file exists at the given `~`-relative path.
    static func fileExists(at tildePath: String) -> Bool {
        let expanded = (tildePath as NSString).expandingTildeInPath
        return FileManager.default.fileExists(atPath: expanded)
    }

    /// Whether a generic-password keychain item with the given service exists.
    ///
    /// Requests attributes only (`kSecReturnData: false`) — it checks presence
    /// without decrypting the secret, so it typically does not surface a keychain
    /// prompt. Reading the actual value (`readKeychainData`) is what may prompt the
    /// first time another app's item is accessed — the OS transparently asking consent.
    static func keychainItemExists(service: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess
    }

    // MARK: - Reading credential values (read-only)
    //
    // The methods below read a credential's *contents* into memory so a data
    // source can extract the bearer token for an endpoint call. The read-only
    // contract still holds: nothing is ever written back, and callers must never
    // log or persist the returned bytes (the token lives in memory only and goes
    // out solely as an `Authorization` header to the provider's own host).

    /// Reads the raw bytes of a `~`-relative file. Returns nil if absent/unreadable.
    static func readFileData(at tildePath: String) -> Data? {
        let expanded = (tildePath as NSString).expandingTildeInPath
        return FileManager.default.contents(atPath: expanded)
    }

    /// Reads a generic-password keychain item's secret value via the Apple-signed
    /// `/usr/bin/security` tool (read-only; never writes).
    ///
    /// Why the CLI tool instead of `SecItemCopyMatching` directly: the macOS
    /// keychain ACL ("Always Allow") binds to the *requesting app's code signature*.
    /// Reading directly from this app means each new build (and, for an unsigned /
    /// ad-hoc app, each launch) is a new identity → the consent dialog re-appears
    /// every time. `/usr/bin/security` has a single stable identity, so one
    /// "Always Allow" persists across rebuilds and refreshes. (This is the approach
    /// the reference app, CodexBar, uses.) App Sandbox is OFF, so spawning a
    /// subprocess is permitted. The token is captured in memory only — never logged.
    static func readKeychainData(service: String) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        // `security -w` prints the secret followed by a newline.
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Data(trimmed.utf8)
    }
}
