import Foundation

/// Every navigable destination. The plan's rule is that every element in every tab is
/// a link, so this enum is the only way anything navigates, on all five platforms.
public enum HawkerRoute: Hashable, Codable, Sendable {
    case asset(String)                       // ChEMBL id
    case target(String)                      // ChEMBL target id
    case pocket(pdbId: String, ccd: String?)
    case stallFiltered(StallFilter)
    case graveyard(GraveyardFacet)
    case method

    /// `hawker://asset/CHEMBL25`
    public init?(url: URL) {
        guard url.scheme == "hawker" else { return nil }
        // A URL like hawker://asset/CHEMBL25 puts "asset" in the host, not the path.
        var parts: [String] = []
        if let host = url.host(), !host.isEmpty { parts.append(host) }
        parts.append(contentsOf: url.pathComponents.filter { $0 != "/" })
        guard let head = parts.first else { return nil }
        let rest = Array(parts.dropFirst())

        switch head.lowercased() {
        case "asset":
            guard let id = rest.first else { return nil }
            self = .asset(id.uppercased())
        case "target":
            guard let id = rest.first else { return nil }
            self = .target(id.uppercased())
        case "pocket":
            guard let pdb = rest.first else { return nil }
            self = .pocket(pdbId: pdb.uppercased(), ccd: rest.dropFirst().first?.uppercased())
        case "graveyard":
            let facet = rest.first.flatMap(GraveyardFacet.init(rawValue:)) ?? .causeByYear
            self = .graveyard(facet)
        case "method":
            self = .method
        case "stall":
            var filter = StallFilter()
            for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
                switch item.name {
                case "cause": filter.causes = Set((item.value ?? "").split(separator: ",").compactMap { CauseOfDeath(rawValue: String($0)) })
                case "phase": filter.phases = Set((item.value ?? "").split(separator: ",").compactMap { TrialPhase(rawValue: String($0)) })
                case "family": filter.families = Set((item.value ?? "").split(separator: ",").compactMap { TargetFamily(rawValue: String($0)) })
                case "structure": filter.requiresStructure = (item.value == "1" || item.value == "true")
                case "fto": filter.requiresLapsedFTO = (item.value == "1" || item.value == "true")
                case "q": filter.query = item.value ?? ""
                default: break
                }
            }
            self = .stallFiltered(filter)
        default:
            return nil
        }
    }

    public var url: URL? {
        switch self {
        case .asset(let id): URL(string: "hawker://asset/\(id)")
        case .target(let id): URL(string: "hawker://target/\(id)")
        case .pocket(let pdb, let ccd):
            URL(string: "hawker://pocket/\(pdb)" + (ccd.map { "/\($0)" } ?? ""))
        case .graveyard(let facet): URL(string: "hawker://graveyard/\(facet.rawValue)")
        case .method: URL(string: "hawker://method")
        case .stallFiltered(let filter): filter.url
        }
    }
}

/// The Stall's filter state, which is also a route so a chart can navigate into a
/// filtered list and the result can be shared as a link.
public struct StallFilter: Hashable, Codable, Sendable {
    public var causes: Set<CauseOfDeath> = []
    public var phases: Set<TrialPhase> = []
    public var families: Set<TargetFamily> = []
    public var requiresStructure = false
    public var requiresLapsedFTO = false
    public var query: String = ""
    public var sort: StallSort = .ghostRank

    public init() {}

    public init(cause: CauseOfDeath) {
        self.causes = [cause]
    }

    public var isActive: Bool {
        !causes.isEmpty || !phases.isEmpty || !families.isEmpty
            || requiresStructure || requiresLapsedFTO || !query.isEmpty
    }

    public func matches(_ asset: Asset) -> Bool {
        if !causes.isEmpty, !causes.contains(asset.cause) { return false }
        if !phases.isEmpty {
            guard let phase = asset.phaseReached, phases.contains(phase) else { return false }
        }
        if !families.isEmpty {
            guard let family = asset.target?.family, families.contains(family) else { return false }
        }
        if requiresStructure, !asset.hasCoCrystal { return false }
        if requiresLapsedFTO, !asset.ftoLapsedEstimate { return false }
        return true
    }

    var url: URL? {
        var components = URLComponents()
        components.scheme = "hawker"
        components.host = "stall"
        var items: [URLQueryItem] = []
        if !causes.isEmpty { items.append(.init(name: "cause", value: causes.map(\.rawValue).sorted().joined(separator: ","))) }
        if !phases.isEmpty { items.append(.init(name: "phase", value: phases.map(\.rawValue).sorted().joined(separator: ","))) }
        if !families.isEmpty { items.append(.init(name: "family", value: families.map(\.rawValue).sorted().joined(separator: ","))) }
        if requiresStructure { items.append(.init(name: "structure", value: "1")) }
        if requiresLapsedFTO { items.append(.init(name: "fto", value: "1")) }
        if !query.isEmpty { items.append(.init(name: "q", value: query)) }
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }

    /// A sentence describing what is being shown, for the list header. Empty states
    /// and filtered states must both say what they are.
    public var summary: String {
        var parts: [String] = []
        if !causes.isEmpty { parts.append(causes.map(\.shortLabel).sorted().joined(separator: ", ")) }
        if !phases.isEmpty { parts.append(phases.sorted { $0.rank < $1.rank }.map(\.shortLabel).joined(separator: ", ")) }
        if !families.isEmpty { parts.append(families.map(\.label).sorted().joined(separator: ", ")) }
        if requiresStructure { parts.append("with a co-crystal") }
        if requiresLapsedFTO { parts.append("estimated horizon passed") }
        return parts.isEmpty ? "All dead assets" : parts.joined(separator: " · ")
    }
}

public enum StallSort: String, Codable, Sendable, CaseIterable, Hashable {
    case ghostRank, benignDeath, tractability, whitespace, fto, name, phase

    public var label: String {
        switch self {
        case .ghostRank: "Ghost Rank"
        case .benignDeath: "Benign death"
        case .tractability: "Tractability"
        case .whitespace: "Whitespace"
        case .fto: "FTO (estimate)"
        case .name: "Name"
        case .phase: "Phase reached"
        }
    }

    public func areInIncreasingOrder(_ a: Asset, _ b: Asset) -> Bool {
        switch self {
        case .ghostRank: a.ghostRank > b.ghostRank
        case .benignDeath: a.score.benignDeath > b.score.benignDeath
        case .tractability: a.score.structuralTractability > b.score.structuralTractability
        case .whitespace: a.score.biologicalWhitespace > b.score.biologicalWhitespace
        case .fto: a.score.freedomToOperate > b.score.freedomToOperate
        case .name: a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        case .phase: (a.phaseReached?.rank ?? 0) > (b.phaseReached?.rank ?? 0)
        }
    }
}

public enum GraveyardFacet: String, Codable, Sendable, CaseIterable, Hashable {
    case causeByYear, causeByTargetClass, rankVsPhase, phaseToCause

    public var label: String {
        switch self {
        case .causeByYear: "Causes of death by year"
        case .causeByTargetClass: "Cause by target class"
        case .rankVsPhase: "Ghost Rank against phase reached"
        case .phaseToCause: "Phase reached to cause of death"
        }
    }
}
