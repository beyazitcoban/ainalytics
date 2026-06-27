import SwiftUI

/// Settings → Providers: turn each provider's tracking on or off. A disabled
/// provider is not fetched and is hidden from the menu bar and dashboard
/// (the single control surface for which providers Ainalytics follows).
struct ProviderSettingsView: View {
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        Form {
            Section {
                ForEach(ProviderID.allCases, id: \.self) { id in
                    Toggle(isOn: enabledBinding(for: id)) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Theme.accent(for: id))
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)
                            Text(verbatim: id.displayName)
                        }
                    }
                }
            } header: {
                Text("Tracked providers")
            } footer: {
                Text("A disabled provider isn't fetched and is hidden from the menu bar and dashboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(ProviderID.allCases, id: \.self) { id in
                    Picker(selection: planBinding(for: id)) {
                        Text("Not set").tag(String?.none)
                        ForEach(PlanPriceCatalog.plans(for: id)) { plan in
                            Text(verbatim: plan.displayName).tag(Optional(plan.key))
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Theme.accent(for: id))
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)
                            Text(verbatim: id.displayName)
                        }
                    }
                }
            } header: {
                Text("Plan")
            } footer: {
                Text("Pick your plan for an automatic price — a typed price below still overrides it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(ProviderID.allCases, id: \.self) { id in
                    LabeledContent {
                        TextField(
                            "per month", value: priceBinding(for: id),
                            format: .currency(code: "USD")
                        )
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Theme.accent(for: id))
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)
                            Text(verbatim: id.displayName)
                        }
                    }
                }
            } header: {
                Text("Price override")
            } footer: {
                Text(
                    "Monthly price for the ROI comparison — leave empty to use your selected plan's price."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func enabledBinding(for id: ProviderID) -> Binding<Bool> {
        Binding(
            get: { preferences.isProviderEnabled(id) },
            set: { preferences.setProvider(id, enabled: $0) })
    }

    /// Optional currency binding: an empty field clears the price (ROI then skips
    /// that provider) rather than storing 0.
    private func priceBinding(for id: ProviderID) -> Binding<Double?> {
        Binding(
            get: { preferences.monthlyPrice(for: id) },
            set: { preferences.setMonthlyPrice($0, for: id) })
    }

    /// Selected-plan binding: `nil` ("Not set") clears the plan.
    private func planBinding(for id: ProviderID) -> Binding<String?> {
        Binding(
            get: { preferences.selectedPlanKey(for: id) },
            set: { preferences.setSelectedPlanKey($0, for: id) })
    }
}

#Preview {
    ProviderSettingsView()
        .environment(AppPreferences())
        .frame(width: 540, height: 400)
}
