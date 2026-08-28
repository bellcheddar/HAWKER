import Foundation

/// A dead clinical asset: the core record the whole app is built around.
public struct Asset: Codable, Sendable, Hashable, Identifiable {
    public var id: String { chemblId }

    // Identity, from ChEMBL.
    public let chemblId: String
    public let prefName: String?
    public let synonyms: [String]
    public let smiles: String?
    public let inchiKey: String?
    /// ChEMBL reports this as a String ("3.0"), parsed here to a Double.
    public let maxPhase: Double?
    public let withdrawnFlag: Bool
    public let firstApproval: Int?
    public let moleculeType: String?

    // Mechanism and target.
    public let mechanismOfAction: String?
    public let actionType: String?
    public let target: TargetRecord?

    // The indication it was actually tested in, from ChEMBL drug_indication.
    public let failedIndications: [Indication]

    // Trials, from ClinicalTrials.gov, reached via UniChem's NCT cross-references.
    public let trials: [TrialRecord]

    // Chemistry cross-references, from UniChem.
    /// PDB chemical component id, the key that finds co-crystals of this exact ligand.
    public let ccdCode: String?
    public let pubchemCID: String?

    // Structures, from RCSB.
    public let structures: [StructureRef]

    // Derived.
    public let verdict: CauseVerdict
    public let score: ResurrectionScore
    /// Estimated composition-of-matter horizon: earliest public date + 20 years.
    /// An estimate, never presented as a freedom-to-operate opinion.
    public let estimatedFTOYear: Int?

    public init(
        chemblId: String,
        prefName: String?,
        synonyms: [String],
        smiles: String?,
        inchiKey: String?,
        maxPhase: Double?,
        withdrawnFlag: Bool,
        firstApproval: Int?,
        moleculeType: String?,
        mechanismOfAction: String?,
        actionType: String?,
        target: TargetRecord?,
        failedIndications: [Indication],
        trials: [TrialRecord],
        ccdCode: String?,
        pubchemCID: String?,
        structures: [StructureRef],
        verdict: CauseVerdict,
        score: ResurrectionScore,
        estimatedFTOYear: Int?
    ) {
        self.chemblId = chemblId
        self.prefName = prefName
        self.synonyms = synonyms
        self.smiles = smiles
        self.inchiKey = inchiKey
        self.maxPhase = maxPhase
        self.withdrawnFlag = withdrawnFlag
        self.firstApproval = firstApproval
        self.moleculeType = moleculeType
        self.mechanismOfAction = mechanismOfAction
        self.actionType = actionType
        self.target = target
        self.failedIndications = failedIndications
        self.trials = trials
        self.ccdCode = ccdCode
        self.pubchemCID = pubchemCID
        self.structures = structures
        self.verdict = verdict
        self.score = score
        self.estimatedFTOYear = estimatedFTOYear
    }

    // MARK: Display

    /// Falls back through synonyms to the ChEMBL id rather than inventing a name.
    public var displayName: String {
        if let prefName, !prefName.isEmpty { return prefName.capitalisedDrugName }
        if let first = synonyms.first { return first }
        return chemblId
    }

    public var cause: CauseOfDeath { verdict.cause }
    public var ghostRank: Int { score.ghostRank }

    /// The highest phase any of its trials reached, preferring the trial record
    /// over ChEMBL's `max_phase` because it is the more specific claim.
    public var phaseReached: TrialPhase? {
        trials.compactMap(\.highestPhase).max(by: { $0.rank < $1.rank }) ?? maxPhase.map(TrialPhase.init(chemblMaxPhase:))
    }

    public var haltedTrials: [TrialRecord] { trials.filter(\.isHalted) }

    /// Year of death: the latest completion of a halted trial.
    public var yearOfDeath: Int? {
        let dates = haltedTrials.compactMap(\.deathDate)
        guard let latest = dates.max() else { return nil }
        return Calendar(identifier: .gregorian).component(.year, from: latest)
    }

    public var hasCoCrystal: Bool { ccdCode != nil && !structures.isEmpty }

    /// True when the estimated horizon has passed. Estimate only.
    public var ftoLapsedEstimate: Bool {
        guard let estimatedFTOYear else { return false }
        return estimatedFTOYear <= Calendar(identifier: .gregorian).component(.year, from: Date())
    }

    /// The single sentence the app exists to answer.
    public var diedOfBusiness: Bool { !cause.isMechanistic && cause != .unknown }

    /// The strongest whitespace association: best genetically supported disease
    /// that is not one of the indications it failed in.
    public var whitespaceAssociation: DiseaseAssociation? {
        guard let target else { return nil }
        let failedIds = Set(failedIndications.map(\.efoId))
        let failedNames = Set(failedIndications.map { $0.term.lowercased() })
        return target.associations
            .filter { !failedIds.contains($0.diseaseId) && !failedNames.contains($0.diseaseName.lowercased()) }
            .max(by: { $0.geneticScore < $1.geneticScore })
    }
}

/// A disease the asset was actually tested against.
public struct Indication: Codable, Sendable, Hashable, Identifiable {
    public var id: String { efoId }
    public let efoId: String
    public let term: String
    public let maxPhaseForIndication: Double?
    /// NCT ids ChEMBL lists as evidence for this indication.
    public let nctIds: [String]

    public init(efoId: String, term: String, maxPhaseForIndication: Double?, nctIds: [String]) {
        self.efoId = efoId
        self.term = term
        self.maxPhaseForIndication = maxPhaseForIndication
        self.nctIds = nctIds
    }
}

extension TrialPhase {
    /// ChEMBL's max_phase is a number on the same scale as the trial phases.
    init(chemblMaxPhase: Double) {
        switch chemblMaxPhase {
        case ..<1: self = .notApplicable
        case ..<2: self = .phase1
        case ..<3: self = .phase2
        case ..<4: self = .phase3
        default:   self = .phase4
        }
    }
}

extension String {
    /// ChEMBL stores preferred names in block capitals ("DARAPLADIB"), which reads
    /// as shouting in a card grid.
    var capitalisedDrugName: String {
        guard self == uppercased() else { return self }
        return prefix(1).uppercased() + dropFirst().lowercased()
    }
}
