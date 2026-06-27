import Foundation
import OSLog

/// Per-million-token prices for one model. `cacheRead`/`cacheWrite` are optional
/// because some catalog entries omit them.
struct ModelPrice: Sendable, Equatable {
    /// USD per 1M input tokens.
    let input: Double
    /// USD per 1M output tokens.
    let output: Double
    /// USD per 1M cache-read tokens (falls back to `input` when absent).
    let cacheRead: Double?
    /// USD per 1M cache-write tokens (falls back to `input` when absent).
    let cacheWrite: Double?
}

/// Resolves a model id to its price. The bundled `model-prices.json` snapshot
/// (captured from models.dev) is the primary table; when reachable, the live
/// models.dev catalog is fetched once and consulted first so newer prices win —
/// the "bundled table + models.dev online fallback" of ARCHITECTURE §2.
///
/// An `actor` so the one-time network fetch is serialized and the cost engine can
/// `await` a refresh before pricing. A model found in neither table prices as
/// `nil` ("price unavailable") — never a guessed number.
actor ModelPriceCatalog {
    private let logger = Logger(subsystem: "com.beyazit.ainalytics", category: "prices")

    /// catalog-provider key → (model id → price). Keys are models.dev provider ids.
    private var bundled: [String: [String: ModelPrice]] = [:]
    private var online: [String: [String: ModelPrice]] = [:]
    private var didAttemptRefresh = false

    init() {
        bundled = Self.loadBundled()
    }

    /// Map our `ProviderID` to the models.dev provider whose catalog holds its models.
    private static func catalogProvider(for provider: ProviderID) -> String {
        switch provider {
        case .claude: "anthropic"
        case .codex: "openai"
        }
    }

    /// Price for a model, or `nil` if neither table knows it. Online is preferred
    /// (fresher); both are tried against normalized id variants.
    func price(for provider: ProviderID, model: String) -> ModelPrice? {
        let catalog = Self.catalogProvider(for: provider)
        let candidates = Self.normalizedCandidates(model)
        for source in [online, bundled] {
            guard let table = source[catalog] else { continue }
            for candidate in candidates {
                if let price = table[candidate] { return price }
            }
        }
        return nil
    }

    /// Fetch the live models.dev catalog once per app run (best-effort). Failures
    /// are logged and ignored — the bundled snapshot already covers current models.
    func refreshIfNeeded() async {
        guard !didAttemptRefresh else { return }
        didAttemptRefresh = true
        guard let url = URL(string: "https://models.dev/api.json") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
            else { return }
            online = Self.parse(catalogData: data)
            logger.notice("models.dev refreshed: \(self.online.values.map(\.count).reduce(0, +)) prices")
        } catch {
            logger.notice("models.dev unreachable; using bundled prices")
        }
    }

    // MARK: - Loading & parsing

    private static func loadBundled() -> [String: [String: ModelPrice]] {
        guard let url = Bundle.main.url(forResource: "model-prices", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return [:] }
        return parseBundled(data)
    }

    /// Decode the app's own snapshot shape: `{ providers: { <provider>: { <id>: {input,…} } } }`.
    private static func parseBundled(_ data: Data) -> [String: [String: ModelPrice]] {
        struct Snapshot: Decodable {
            let providers: [String: [String: RawPrice]]
        }
        struct RawPrice: Decodable {
            let input: Double
            let output: Double
            let cache_read: Double?
            let cache_write: Double?
        }
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return [:] }
        return snapshot.providers.mapValues { models in
            models.mapValues {
                ModelPrice(
                    input: $0.input, output: $0.output, cacheRead: $0.cache_read,
                    cacheWrite: $0.cache_write)
            }
        }
    }

    /// Extract anthropic/openai/google cost tables from the live models.dev shape:
    /// `{ <provider>: { models: { <id>: { cost: {input,output,cache_read,cache_write} } } } }`.
    private static func parse(catalogData data: Data) -> [String: [String: ModelPrice]] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var result: [String: [String: ModelPrice]] = [:]
        for catalog in ["anthropic", "openai", "google"] {
            guard let provider = root[catalog] as? [String: Any],
                let models = provider["models"] as? [String: Any]
            else { continue }
            var table: [String: ModelPrice] = [:]
            for (id, value) in models {
                guard let model = value as? [String: Any],
                    let cost = model["cost"] as? [String: Any],
                    let input = (cost["input"] as? NSNumber)?.doubleValue,
                    let output = (cost["output"] as? NSNumber)?.doubleValue
                else { continue }
                table[id] = ModelPrice(
                    input: input, output: output,
                    cacheRead: (cost["cache_read"] as? NSNumber)?.doubleValue,
                    cacheWrite: (cost["cache_write"] as? NSNumber)?.doubleValue)
            }
            result[catalog] = table
        }
        return result
    }

    /// Ordered id variants to try: the id as-is, dash↔dot swaps, and the id with a
    /// trailing `-YYYYMMDD` snapshot suffix stripped (e.g. `claude-opus-4-1-20250805`).
    private static func normalizedCandidates(_ model: String) -> [String] {
        var candidates = [model]
        let dotted = model.replacingOccurrences(of: "-", with: ".")
        let dashed = model.replacingOccurrences(of: ".", with: "-")
        candidates.append(contentsOf: [dotted, dashed])
        if let range = model.range(of: "-[0-9]{8}$", options: .regularExpression) {
            candidates.append(String(model[..<range.lowerBound]))
        }
        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }
}
