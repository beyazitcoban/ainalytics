#if DEBUG
    import SwiftUI

    /// Debug raw-data view (Critical Pass #4): each provider's parsed usage numbers
    /// shown next to the unparsed endpoint body, so displayed values can be verified
    /// against source without reading code. DEBUG-only; lives behind the Developer tab.
    /// Holds usage numbers only — never the token.
    struct DebugDataView: View {
        @Environment(AppState.self) private var appState

        var body: some View {
            List {
                ForEach(ProviderID.allCases, id: \.self) { id in
                    Section(id.displayName) {
                        providerSection(appState.runtime(for: id))
                    }
                }
            }
            .frame(minWidth: 480, minHeight: 360)
        }

        @ViewBuilder private func providerSection(_ runtime: ProviderRuntime) -> some View {
            LabeledContent("Connection", value: runtime.connection.persistedRaw)

            if let fetched = runtime.lastFetched {
                LabeledContent("Last fetched") { Text(fetched, style: .relative) }
            }
            if let error = runtime.errorMessage {
                LabeledContent("Error", value: error)
            }

            if runtime.windows.isEmpty {
                Text("No windows parsed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(runtime.windows) { window in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(window.id).font(.caption.bold())
                        Text(
                            "used \(window.used, format: .number.precision(.fractionLength(1))) / \(window.limit, format: .number.precision(.fractionLength(0))) → \(Int(window.percentRemaining))% left"
                        )
                        .font(.caption)
                        .monospacedDigit()
                        if let reset = window.resetsAt {
                            Text("resets: \(reset.formatted())")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let raw = runtime.rawResponse {
                DisclosureGroup("Raw response") {
                    Text(raw)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
#endif
