import Foundation

/// A protein target assembled from ChEMBL (identity) and Open Targets
/// (tractability, safety, disease associations).
public struct TargetRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: String { chemblId }

    public let chemblId: String
    public let prefName: String
    public let targetType: String?
    public let organism: String?
    public let uniprotAccession: String?
    public let ensemblId: String?
    public let approvedSymbol: String?
    /// Open Targets target-class labels, deepest level first.
    public let targetClasses: [String]
    /// Small-molecule tractability labels that came back `true`.
    public let tractabilitySM: [String]
    public let safetyLiabilities: [SafetyLiability]
    /// Disease associations, best score first, capped at the top 25.
    public let associations: [DiseaseAssociation]

    public init(
        chemblId: String,
        prefName: String,
        targetType: String?,
        organism: String?,
        uniprotAccession: String?,
        ensemblId: String?,
        approvedSymbol: String?,
        targetClasses: [String],
        tractabilitySM: [String],
        safetyLiabilities: [SafetyLiability],
        associations: [DiseaseAssociation]
    ) {
        self.chemblId = chemblId
        self.prefName = prefName
        self.targetType = targetType
        self.organism = organism
        self.uniprotAccession = uniprotAccession
        self.ensemblId = ensemblId
        self.approvedSymbol = approvedSymbol
        self.targetClasses = targetClasses
        self.tractabilitySM = tractabilitySM
        self.safetyLiabilities = safetyLiabilities
        self.associations = associations
    }

    /// Coarse family used to group the Graveyard's per-class bars.
    public var family: TargetFamily { TargetFamily(classes: targetClasses, name: prefName) }

    public var displayName: String { approvedSymbol ?? prefName }
}

public struct SafetyLiability: Codable, Sendable, Hashable {
    public let event: String?
    public let eventId: String?
    public let datasource: String?

    public init(event: String?, eventId: String?, datasource: String?) {
        self.event = event
        self.eventId = eventId
        self.datasource = datasource
    }
}

public struct DiseaseAssociation: Codable, Sendable, Hashable, Identifiable {
    public var id: String { diseaseId }

    public let diseaseId: String
    public let diseaseName: String
    /// Overall Open Targets association score, 0 to 1.
    public let score: Double
    /// Per-datatype scores, keyed by Open Targets datatype id.
    public let datatypeScores: [String: Double]

    public init(diseaseId: String, diseaseName: String, score: Double, datatypeScores: [String: Double]) {
        self.diseaseId = diseaseId
        self.diseaseName = diseaseName
        self.score = score
        self.datatypeScores = datatypeScores
    }

    /// The genetic evidence component, which is what makes a whitespace claim
    /// worth anything: literature co-mention alone is not evidence of causality.
    public var geneticScore: Double {
        max(datatypeScores["genetic_association"] ?? 0, datatypeScores["genetic_literature"] ?? 0)
    }
}

public enum TargetFamily: String, Codable, Sendable, CaseIterable, Hashable {
    case kinase, gpcr, protease, ionChannel, nuclearReceptor, transporter, enzymeOther, other

    init(classes: [String], name: String) {
        let hay = (classes + [name]).joined(separator: " ").lowercased()
        if hay.contains("kinase") { self = .kinase }
        else if hay.contains("gpcr") || hay.contains("g protein-coupled") || hay.contains("7tm") { self = .gpcr }
        else if hay.contains("protease") || hay.contains("peptidase") { self = .protease }
        else if hay.contains("ion channel") || hay.contains("channel") { self = .ionChannel }
        else if hay.contains("nuclear receptor") { self = .nuclearReceptor }
        else if hay.contains("transporter") || hay.contains("slc") { self = .transporter }
        else if hay.contains("enzyme") || hay.contains("transferase") || hay.contains("reductase")
                 || hay.contains("hydrolase") || hay.contains("oxidase") { self = .enzymeOther }
        else { self = .other }
    }

    public var label: String {
        switch self {
        case .kinase: "Kinase"
        case .gpcr: "GPCR"
        case .protease: "Protease"
        case .ionChannel: "Ion channel"
        case .nuclearReceptor: "Nuclear receptor"
        case .transporter: "Transporter"
        case .enzymeOther: "Enzyme (other)"
        case .other: "Other"
        }
    }
}
