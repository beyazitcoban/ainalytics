import Foundation

/// How a usage peak fits a candidate plan.
enum PlanFitVerdict: Sendable, Equatable {
    /// Comfortable — the projected peak leaves headroom.
    case fits
    /// Cuts it close — the projected peak is near the cap.
    case tight
    /// The projected peak exceeds the cap — the plan can't hold it.
    case over
}

/// One candidate plan's fit for the observed peak usage.
struct PlanFitResult: Identifiable, Sendable, Equatable {
    let plan: PlanOption
    /// The peak utilization the user would see on this plan (percent of its cap).
    let projectedPeak: Double
    let verdict: PlanFitVerdict
    /// Whether this is the user's current plan.
    let isCurrent: Bool
    var id: String { plan.key }
}

/// Right-sizing: given the user's peak utilization on their current plan, project it
/// onto every plan of the same provider and classify the fit. Pure and testable.
///
/// A plan's multiplier scales every window's limit proportionally, so a peak of `P%`
/// on a plan of capacity `C` becomes `P × C / C'` on a plan of capacity `C'`. Only
/// plans with a known `relativeCapacity` participate (ChatGPT Go is excluded — no
/// clean published multiple, never guessed).
enum PlanFit {
    /// At or below this projected peak a plan "fits" (comfortable headroom).
    static let fitsThreshold: Double = 85
    /// Above this projected peak a plan is "over" (cannot hold the peak).
    static let overThreshold: Double = 100

    static func verdict(forProjectedPeak peak: Double) -> PlanFitVerdict {
        if peak > overThreshold { return .over }
        if peak > fitsThreshold { return .tight }
        return .fits
    }

    /// Project `currentPeak` (percent of the current plan's cap) onto `candidate`.
    /// `nil` if either plan lacks a known capacity.
    static func projectedPeak(
        currentPeak: Double, current: PlanOption, candidate: PlanOption
    ) -> Double? {
        guard let cur = current.relativeCapacity, let cand = candidate.relativeCapacity,
            cand > 0
        else { return nil }
        return currentPeak * cur / cand
    }

    /// Every candidate plan for `provider` (including the current one) with its fit,
    /// in ascending capacity order. Empty when the current plan is unknown or has no
    /// known capacity.
    static func results(
        provider: ProviderID, currentKey: String, currentPeak: Double
    ) -> [PlanFitResult] {
        guard let current = PlanPriceCatalog.plan(for: provider, key: currentKey),
            current.relativeCapacity != nil
        else { return [] }
        return
            PlanPriceCatalog.plans(for: provider)
            .compactMap { candidate -> PlanFitResult? in
                guard
                    let projected = projectedPeak(
                        currentPeak: currentPeak, current: current, candidate: candidate)
                else { return nil }
                return PlanFitResult(
                    plan: candidate, projectedPeak: projected,
                    verdict: verdict(forProjectedPeak: projected),
                    isCurrent: candidate.key == current.key)
            }
            .sorted { ($0.plan.relativeCapacity ?? 0) < ($1.plan.relativeCapacity ?? 0) }
    }

    /// The recommended plan: the smallest-capacity plan that still fits the peak.
    /// Because the current plan's own projected peak is the observed peak (≤ 100),
    /// the current plan always at least "tight"-fits, so a recommendation exists
    /// whenever there is data; it equals the current plan when nothing smaller fits.
    static func recommendation(
        provider: ProviderID, currentKey: String, currentPeak: Double
    ) -> PlanOption? {
        let all = results(provider: provider, currentKey: currentKey, currentPeak: currentPeak)
        if let smallestFitting = all.first(where: { $0.verdict == .fits }) {
            return smallestFitting.plan
        }
        // Nothing comfortably fits (even the current plan is "tight") → keep current.
        return all.first(where: { $0.isCurrent })?.plan
    }
}
