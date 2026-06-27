import AppKit
import SwiftUI

/// App-wide user preferences. Per the stack's state-management discipline,
/// app-wide config is an `@Observable` class persisted via `UserDefaults`
/// (not scattered `@AppStorage`, not SwiftData). None of these are secrets.
@MainActor
@Observable
final class AppPreferences {

    /// Whether the app shows a Dock icon. Default false → menu-bar-primary.
    /// Flipping it applies the activation policy at runtime (no relaunch).
    var showDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: Keys.showDockIcon)
            Self.syncActivationPolicy()
        }
    }

    /// The provider whose live headline usage % + monochrome logo is shown directly
    /// in the menu-bar item (the "menu-bar provider mode"). Empty → the app shows its
    /// generic glyph (the default). Stored as the raw provider id; read through the
    /// `menuBarProvider` helper so a disabled provider is never headlined.
    var menuBarProviderID: String {
        didSet {
            UserDefaults.standard.set(menuBarProviderID, forKey: Keys.menuBarProvider)
        }
    }

    /// How the menu-bar item renders the pinned provider's usage (logo + %, % only, or
    /// logo + name + %). Only takes effect when a provider is pinned; with no pin the
    /// menu bar shows the app's generic glyph and no percentage. Default: logo + %.
    var menuBarStyle: MenuBarStyle {
        didSet { UserDefaults.standard.set(menuBarStyle.rawValue, forKey: Keys.menuBarStyle) }
    }

    /// How a window's reset/renewal time is shown across the menu bar + dashboard:
    /// a relative, self-updating countdown ("4 sa. sonra sıfırlanır") or an absolute
    /// time ("14:30'da sıfırlanır"). Default: relative duration. Applied through the
    /// shared `ResetTimeFormatter` at all three display sites.
    var resetDisplayStyle: ResetDisplayStyle {
        didSet { UserDefaults.standard.set(resetDisplayStyle.rawValue, forKey: Keys.resetDisplayStyle) }
    }

    /// Selected language code; empty string follows the system language. Writing
    /// it also sets `AppleLanguages` so the chosen localization takes effect — on
    /// the **next launch** (macOS cannot hot-swap a bundle's language at runtime).
    var languageCode: String {
        didSet {
            UserDefaults.standard.set(languageCode, forKey: Keys.language)
            applyLanguageOverride()
        }
    }

    /// Provider ids the user has turned off (raw values). A disabled provider is
    /// not fetched and is hidden from the menu bar + dashboard. Absent → all on.
    var disabledProviderIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(disabledProviderIDs), forKey: Keys.disabledProviders)
        }
    }

    /// Usage refresh cadence (minutes). Consumed by the Phase 2 poller.
    var refreshIntervalMinutes: Int {
        didSet { UserDefaults.standard.set(refreshIntervalMinutes, forKey: Keys.refreshInterval) }
    }

    /// Master switch for usage notifications (threshold + reset). Default on.
    var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
        }
    }

    /// Usage-percent levels that fire a one-shot warning when first crossed
    /// (re-armed on recovery). Chosen from `selectableThresholds`. Default both.
    var enabledThresholds: Set<Int> {
        didSet {
            UserDefaults.standard.set(enabledThresholds.sorted(), forKey: Keys.enabledThresholds)
        }
    }

    /// Whether a window rolling over posts a "limit reset" notification. Default on.
    var resetNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(
                resetNotificationsEnabled, forKey: Keys.resetNotificationsEnabled)
        }
    }

    /// Provider ids muted for notifications (raw values). Absent → every provider notifies.
    var mutedProviderIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(mutedProviderIDs), forKey: Keys.mutedProviders)
        }
    }

    /// The user's monthly subscription price per provider (raw id → USD), used only
    /// for the ROI / "is it worth it" comparison. Not a secret, user-supplied, and
    /// absent for any provider whose price hasn't been entered (ROI is then skipped).
    var providerMonthlyPriceUSD: [String: Double] {
        didSet {
            UserDefaults.standard.set(providerMonthlyPriceUSD, forKey: Keys.providerPrices)
        }
    }

    /// The entered monthly price for a provider, or `nil` when unset / non-positive
    /// (so the ROI view shows a prompt instead of a misleading 0).
    func monthlyPrice(for id: ProviderID) -> Double? {
        guard let price = providerMonthlyPriceUSD[id.rawValue], price > 0 else { return nil }
        return price
    }

    /// Set (or, with `nil`/0, clear) a provider's monthly subscription price.
    func setMonthlyPrice(_ price: Double?, for id: ProviderID) {
        if let price, price > 0 {
            providerMonthlyPriceUSD[id.rawValue] = price
        } else {
            providerMonthlyPriceUSD.removeValue(forKey: id.rawValue)
        }
    }

    /// The subscription plan the user selected per provider (raw id → `PlanPriceCatalog`
    /// plan key). The endpoints don't reliably expose the plan, so the user picks it;
    /// the selection drives the auto ROI price (a manual price still overrides). Absent
    /// for any provider whose plan hasn't been chosen.
    var selectedPlanByProvider: [String: String] {
        didSet {
            UserDefaults.standard.set(selectedPlanByProvider, forKey: Keys.selectedPlans)
        }
    }

    /// The selected plan key for a provider, or `nil` when unset.
    func selectedPlanKey(for id: ProviderID) -> String? {
        selectedPlanByProvider[id.rawValue]
    }

    /// Select (or, with `nil`, clear) a provider's subscription plan.
    func setSelectedPlanKey(_ key: String?, for id: ProviderID) {
        if let key {
            selectedPlanByProvider[id.rawValue] = key
        } else {
            selectedPlanByProvider.removeValue(forKey: id.rawValue)
        }
    }

    /// The usage-percent levels the Settings UI offers as warning toggles.
    static let selectableThresholds = [80, 95]

    /// The refresh cadences (minutes) the Settings UI offers.
    static let selectableRefreshIntervals = [1, 5, 15, 30, 60]

    /// Providers currently tracked (all minus the disabled set), in stable order.
    var enabledProviderIDs: [ProviderID] {
        ProviderID.allCases.filter { !disabledProviderIDs.contains($0.rawValue) }
    }

    func isProviderEnabled(_ id: ProviderID) -> Bool {
        !disabledProviderIDs.contains(id.rawValue)
    }

    func setProvider(_ id: ProviderID, enabled: Bool) {
        if enabled {
            disabledProviderIDs.remove(id.rawValue)
        } else {
            disabledProviderIDs.insert(id.rawValue)
        }
    }

    /// The provider selected for the menu-bar item, or `nil` when the menu bar shows
    /// the app's generic glyph (the default). A disabled provider reads as unselected
    /// so the menu bar never headlines a provider the user turned off.
    var menuBarProvider: ProviderID? {
        guard let id = ProviderID(rawValue: menuBarProviderID), isProviderEnabled(id) else {
            return nil
        }
        return id
    }

    /// Select (or, with `nil`, clear) the provider headlined in the menu-bar item.
    func setMenuBarProvider(_ id: ProviderID?) {
        menuBarProviderID = id?.rawValue ?? ""
    }

    init() {
        let defaults = UserDefaults.standard
        showDockIcon = defaults.bool(forKey: Keys.showDockIcon)
        menuBarProviderID = defaults.string(forKey: Keys.menuBarProvider) ?? ""
        menuBarStyle =
            MenuBarStyle(rawValue: defaults.string(forKey: Keys.menuBarStyle) ?? "") ?? .logoPercent
        resetDisplayStyle =
            ResetDisplayStyle(rawValue: defaults.string(forKey: Keys.resetDisplayStyle) ?? "")
            ?? .relativeDuration
        languageCode = defaults.string(forKey: Keys.language) ?? ""
        disabledProviderIDs = Set(defaults.array(forKey: Keys.disabledProviders) as? [String] ?? [])
        let storedInterval = defaults.integer(forKey: Keys.refreshInterval)
        refreshIntervalMinutes = storedInterval == 0 ? 5 : storedInterval

        // Bool prefs default to `true`, so read via `object(forKey:)` — `bool(forKey:)`
        // can't tell "absent" from "stored false".
        notificationsEnabled = (defaults.object(forKey: Keys.notificationsEnabled) as? Bool) ?? true
        if let storedThresholds = defaults.array(forKey: Keys.enabledThresholds) as? [Int] {
            enabledThresholds = Set(storedThresholds)
        } else {
            enabledThresholds = Set(Self.selectableThresholds)
        }
        resetNotificationsEnabled =
            (defaults.object(forKey: Keys.resetNotificationsEnabled) as? Bool) ?? true
        mutedProviderIDs = Set(defaults.array(forKey: Keys.mutedProviders) as? [String] ?? [])
        providerMonthlyPriceUSD =
            (defaults.dictionary(forKey: Keys.providerPrices) as? [String: Double]) ?? [:]
        selectedPlanByProvider =
            (defaults.dictionary(forKey: Keys.selectedPlans) as? [String: String]) ?? [:]

        Self.syncActivationPolicy()
    }

    /// Set the activation policy from the current window state and the "Show dock
    /// icon" preference: **regular** (Dock icon + owns the system menu bar) when a
    /// content window — the dashboard or the Settings window — is open OR the
    /// preference is on; **accessory** (menu-bar-only agent) otherwise. Called at
    /// launch, when the preference toggles, and on window open/close (`AppDelegate`).
    /// A regular app is the only one that owns the menu bar, so an open dashboard
    /// now shows "Ainalytics" up top instead of the previously-active app.
    static func syncActivationPolicy() {
        let showDock = UserDefaults.standard.bool(forKey: Keys.showDockIcon)
        // The menu-bar popover is borderless (not `.titled`), so it never counts —
        // only real content windows (dashboard / Settings) flip the policy.
        let hasContentWindow = NSApplication.shared.windows.contains {
            $0.isVisible && $0.styleMask.contains(.titled)
        }
        let policy: NSApplication.ActivationPolicy =
            (showDock || hasContentWindow) ? .regular : .accessory
        guard NSApplication.shared.activationPolicy() != policy else { return }
        NSApplication.shared.setActivationPolicy(policy)
        if policy == .regular {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    /// Push the language choice into `AppleLanguages` (read by the localization
    /// system at launch). Empty selection removes the override so the app follows
    /// the system language again. Takes effect on the next launch.
    private func applyLanguageOverride() {
        let defaults = UserDefaults.standard
        if languageCode.isEmpty {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([languageCode], forKey: "AppleLanguages")
        }
    }

    private enum Keys {
        static let showDockIcon = "pref.showDockIcon"
        static let menuBarProvider = "pref.menuBarProviderID"
        static let menuBarStyle = "pref.menuBarStyle"
        static let resetDisplayStyle = "pref.resetDisplayStyle"
        static let language = "pref.language"
        static let refreshInterval = "pref.refreshIntervalMinutes"
        static let notificationsEnabled = "pref.notificationsEnabled"
        static let enabledThresholds = "pref.enabledThresholds"
        static let resetNotificationsEnabled = "pref.resetNotificationsEnabled"
        static let mutedProviders = "pref.mutedProviderIDs"
        static let disabledProviders = "pref.disabledProviderIDs"
        static let providerPrices = "pref.providerMonthlyPriceUSD"
        static let selectedPlans = "pref.selectedPlanByProvider"
    }
}

/// How the menu-bar item renders the pinned provider's usage (the Settings → General →
/// Menu Bar choice). Only takes effect when a provider is pinned; with no pin the menu
/// bar shows the app's own glyph and no percentage.
enum MenuBarStyle: String, CaseIterable, Identifiable {
    /// The provider's monochrome logo followed by its remaining percentage.
    case logoPercent
    /// The remaining percentage only — no logo.
    case percentOnly
    /// The logo, the provider name, and the remaining percentage.
    case logoNamePercent

    var id: String { rawValue }

    /// The localized label shown in the Settings picker.
    var pickerLabel: LocalizedStringKey {
        switch self {
        case .logoPercent: "Logo and percentage"
        case .percentOnly: "Percentage only"
        case .logoNamePercent: "Logo, name and percentage"
        }
    }
}

/// How reset/renewal times are displayed (the Settings → General → "Reset display"
/// choice). Applied everywhere through the shared `ResetTimeFormatter`.
enum ResetDisplayStyle: String, CaseIterable, Identifiable {
    /// A relative, self-updating countdown — "4 sa. sonra sıfırlanır".
    case relativeDuration
    /// An absolute time — "14:30'da sıfırlanır" (same-day → time only, else weekday + time).
    case absoluteTime

    var id: String { rawValue }

    /// The localized label shown in the Settings picker.
    var pickerLabel: LocalizedStringKey {
        switch self {
        case .relativeDuration: "Duration"
        case .absoluteTime: "Exact time"
        }
    }
}
