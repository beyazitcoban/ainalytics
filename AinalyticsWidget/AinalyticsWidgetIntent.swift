import AppIntents

/// Right-click → "Edit Widget" configuration: which provider the widget headlines
/// and which usage window it shows. Both default to the most useful choice
/// (Automatic provider, Session window).
struct AinalyticsWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Usage"
    static let description = IntentDescription("Choose the provider and usage window to show.")

    @Parameter(title: "Provider", default: .automatic)
    var provider: ProviderChoice

    @Parameter(title: "Window", default: .session)
    var window: WindowChoice
}

/// Which provider the widget headlines. `automatic` = the menu-bar-pinned provider,
/// else the one closest to its limit.
enum ProviderChoice: String, AppEnum {
    case automatic
    case claude
    case codex
    case gemini

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Provider")
    static let caseDisplayRepresentations: [ProviderChoice: DisplayRepresentation] = [
        .automatic: "Automatic",
        .claude: "Claude",
        .codex: "ChatGPT / Codex",
        .gemini: "Gemini",
    ]

    /// `ProviderID.rawValue` for an explicit choice, or `nil` for Automatic.
    var providerRaw: String? { self == .automatic ? nil : rawValue }
}

/// Which usage window the widget shows. Maps onto the shared `WindowMetric`.
enum WindowChoice: String, AppEnum {
    case auto
    case session
    case weekly
    case monthly

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Window")
    static let caseDisplayRepresentations: [WindowChoice: DisplayRepresentation] = [
        .auto: "Automatic",
        .session: "Session",
        .weekly: "Weekly",
        .monthly: "Monthly",
    ]

    var metric: WindowMetric {
        switch self {
        case .auto: .auto
        case .session: .session
        case .weekly: .weekly
        case .monthly: .monthly
        }
    }
}
