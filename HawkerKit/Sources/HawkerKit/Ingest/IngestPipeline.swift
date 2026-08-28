import Foundation

/// Builds the working set of dead assets by joining seven public APIs.
///
/// The join, as it actually runs (the build plan's version reached
/// ClinicalTrials.gov by matching drug names; UniChem turned out to carry curated
/// NCT cross-references, so it does not need to):
///
/// ```
/// ChEMBL molecules at max_phase 2 or 3        (reached the clinic)
///   -> ChEMBL mechanism + drug_indication, BATCHED via __in filters
///   -> NCT ids come from indication_refs, so no drug-name matching is needed
///   -> ClinicalTrials.gov by id, 50 at a time  (statuses, phases, whyStopped)
///   -> APPLY THE KEEP RULE HERE
///   then, for survivors only:
///   -> UniChem   -> CCD code and PubChem CID
///   -> ChEMBL target -> UniProt -> Open Targets (tractability, safety, associations)
///   -> RCSB      -> co-crystals of this exact ligand
/// keep if: withdrawn, or any trial halted, or clinical with no recent activity
/// ```
///
/// The ordering is the whole performance story. A first version called UniChem, the
/// mechanism endpoint and the indication endpoint once per molecule, which at the
/// 200 ms per-host spacing this client keeps meant roughly 70 minutes for 2,000
/// molecules. Batching the two ChEMBL endpoints and deferring UniChem until after the
/// keep rule cuts EBI traffic by about 85%, because most molecules are discarded
/// before anything expensive is spent on them.
public actor IngestPipeline {

    public struct Progress: Sendable, Hashable {
        public var stage: String = "Waiting"
        public var completed: Int = 0
        public var total: Int = 0
        public var kept: Int = 0
        public var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    }

    public struct Summary: Sendable {
        public let considered: Int
        public let kept: Int
        public let byCause: [CauseOfDeath: Int]
        public let withCoCrystal: Int
        public let withTarget: Int
        public let elapsed: Duration

        /// The headline the app exists to report.
        public var businessFraction: Double {
            let classified = byCause.filter { $0.key != .unknown }
            let total = classified.values.reduce(0, +)
            guard total > 0 else { return 0 }
            let business = classified.filter { !$0.key.isMechanistic }.values.reduce(0, +)
            return Double(business) / Double(total)
        }
    }

    private let chembl: ChEMBLClient
    private let unichem: UniChemClient
    private let trials: ClinicalTrialsClient
    private let openTargets: OpenTargetsClient
    private let rcsb: RCSBClient
    private let classifier = CauseClassifier()
    private let scorer = Scorer()
    private let whitespace = WhitespaceMatcher()
    private let bank: ExemplarBank

    /// Targets are shared across many molecules, so this cache is the difference
    /// between one Open Targets round trip per asset and one per target.
    private var targetCache: [String: TargetRecord?] = [:]

    public init(
        chembl: ChEMBLClient = ChEMBLClient(),
        unichem: UniChemClient = UniChemClient(),
        trials: ClinicalTrialsClient = ClinicalTrialsClient(),
        openTargets: OpenTargetsClient = OpenTargetsClient(),
        rcsb: RCSBClient = RCSBClient(),
        bank: ExemplarBank = .shared
    ) {
        self.chembl = chembl
        self.unichem = unichem
        self.trials = trials
        self.openTargets = openTargets
        self.rcsb = rcsb
        self.bank = bank
    }

    /// Seed the working set. `limit` bounds the ChEMBL sweep so a cold start finishes
    /// in minutes; a background refresh widens it later.
    public func run(
        limit: Int = 2_000,
        phases: [Int] = [2, 3],
        onProgress: @Sendable @escaping (Progress) -> Void = { _ in }
    ) async throws -> (assets: [Asset], summary: Summary) {
        let clock = ContinuousClock()
        var progress = Progress(stage: "Preparing the on-device classifier", total: limit)
        onProgress(progress)

        // Embedding the exemplar bank costs about nine seconds and only has to happen
        // once, so it runs while nothing else needs the Neural Engine.
        await bank.prepare()

        var molecules: [ChEMBLClient.Molecule] = []
        progress.stage = "Fetching clinical molecules from ChEMBL"
        onProgress(progress)

        // Withdrawn drugs first: they are the highest-value records and far rarer than
        // the phase sweep, so a truncated run still contains the interesting ones.
        molecules.append(contentsOf: try await sweepWithdrawn(limit: min(limit / 4, 500)))
        for phase in phases {
            guard molecules.count < limit else { break }
            molecules.append(contentsOf: try await sweep(
                phase: phase,
                limit: (limit - molecules.count) / max(1, phases.count)
            ))
        }
        var seen = Set<String>()
        molecules = molecules.filter { seen.insert($0.moleculeChemblId).inserted }

        let ids = molecules.map(\.moleculeChemblId)
        progress.total = molecules.count
        progress.stage = "Batch-fetching mechanisms and indications"
        onProgress(progress)

        let mechanismsById = (try? await chembl.mechanisms(moleculeIds: ids)) ?? [:]
        let indicationsById = (try? await chembl.indications(moleculeIds: ids)) ?? [:]

        progress.stage = "Fetching trials from ClinicalTrials.gov"
        onProgress(progress)

        // One flat request set for every NCT the whole batch mentions, then demultiplex.
        var nctsByMolecule: [String: [String]] = [:]
        var allNCTs = Set<String>()
        for id in ids {
            let ncts = (indicationsById[id] ?? []).flatMap(\.nctIds)
            let unique = Array(Set(ncts))
            nctsByMolecule[id] = unique
            allNCTs.formUnion(unique)
        }
        let fetched = (try? await trials.studies(nctIds: Array(allNCTs))) ?? []
        let trialsById = Dictionary(fetched.map { ($0.nctId, $0) }, uniquingKeysWith: { a, _ in a })

        progress.stage = "Applying the keep rule"
        onProgress(progress)

        // The keep rule runs on data that is now already in memory, so the expensive
        // per-asset work below only ever touches assets that survive it.
        struct Candidate: Sendable {
            let molecule: ChEMBLClient.Molecule
            let mechanism: ChEMBLClient.Mechanism?
            let indications: [Indication]
            let trials: [TrialRecord]
        }
        var candidates: [Candidate] = []
        for molecule in molecules {
            let id = molecule.moleculeChemblId
            let records = (nctsByMolecule[id] ?? []).compactMap { trialsById[$0] }
            let withdrawn = molecule.withdrawnFlag == true
            let anyHalted = records.contains { $0.isHalted }
            let clinical = (molecule.maxPhase ?? 0) >= 2
            // "Went quiet" requires trials that then went quiet. Without the
            // `!records.isEmpty` clause this kept every molecule ChEMBL has no trial
            // cross-references for, which on a 1,591-molecule run was 95% of them:
            // absence of evidence read as evidence of death. A compound we know
            // nothing about is not a dead asset, it is an unknown one.
            let wentQuiet = clinical
                && molecule.firstApproval == nil
                && !records.isEmpty
                && !hasRecentActivity(records)
            guard withdrawn || anyHalted || wentQuiet else { continue }

            let indications = (indicationsById[id] ?? []).compactMap { raw -> Indication? in
                guard let efoId = raw.efoId, let term = raw.efoTerm else { return nil }
                return Indication(efoId: efoId, term: term,
                                  maxPhaseForIndication: raw.maxPhaseForInd, nctIds: raw.nctIds)
            }
            candidates.append(Candidate(
                molecule: molecule,
                mechanism: mechanismsById[id]?.first,
                indications: indications,
                trials: records
            ))
        }

        progress.total = candidates.count
        progress.completed = 0
        progress.stage = "Joining targets and structures for \(candidates.count) survivors"
        onProgress(progress)

        var assets: [Asset] = []
        var byCause: [CauseOfDeath: Int] = [:]

        let elapsed = try await clock.measure {
            // Bounded concurrency in fixed windows. The APIClient actor already
            // throttles per host, so a wider fan-out only queues work without
            // finishing it sooner. Windows rather than a sliding pool because Swift 6
            // will not let a nested refill closure capture the group and the cursor.
            let width = 8
            for window in stride(from: 0, to: candidates.count, by: width) {
                let slice = Array(candidates[window..<min(window + width, candidates.count)])
                let batch: [Asset] = try await withThrowingTaskGroup(of: Asset?.self) { group in
                    for candidate in slice {
                        group.addTask { [self] in
                            await enrich(
                                molecule: candidate.molecule,
                                mechanism: candidate.mechanism,
                                indications: candidate.indications,
                                trials: candidate.trials
                            )
                        }
                    }
                    var found: [Asset] = []
                    for try await result in group {
                        if let result { found.append(result) }
                    }
                    return found
                }
                for asset in batch {
                    assets.append(asset)
                    byCause[asset.cause, default: 0] += 1
                }
                progress.completed = min(window + width, candidates.count)
                progress.kept = assets.count
                onProgress(progress)
            }
        }

        assets.sort { $0.ghostRank > $1.ghostRank }
        progress.stage = "Done"
        progress.completed = candidates.count
        onProgress(progress)

        return (assets, Summary(
            considered: molecules.count,
            kept: assets.count,
            byCause: byCause,
            withCoCrystal: assets.filter(\.hasCoCrystal).count,
            withTarget: assets.filter { $0.target != nil }.count,
            elapsed: elapsed
        ))
    }

    // MARK: Sweeps

    private func sweep(phase: Int, limit: Int) async throws -> [ChEMBLClient.Molecule] {
        var out: [ChEMBLClient.Molecule] = []
        var offset = 0
        while out.count < limit {
            let page = try await chembl.molecules(
                maxPhase: phase, limit: min(100, limit - out.count), offset: offset
            )
            if page.molecules.isEmpty { break }
            out.append(contentsOf: page.molecules)
            offset += page.molecules.count
            if page.pageMeta.next == nil { break }
        }
        return out
    }

    private func sweepWithdrawn(limit: Int) async throws -> [ChEMBLClient.Molecule] {
        var out: [ChEMBLClient.Molecule] = []
        var offset = 0
        while out.count < limit {
            let page = try await chembl.withdrawnMolecules(limit: min(100, limit - out.count), offset: offset)
            if page.molecules.isEmpty { break }
            out.append(contentsOf: page.molecules)
            offset += page.molecules.count
            if page.pageMeta.next == nil { break }
        }
        return out
    }

    // MARK: Per-asset enrichment, for survivors only

    /// Everything that costs a request per asset. Only ever called for molecules that
    /// already passed the keep rule.
    func enrich(
        molecule: ChEMBLClient.Molecule,
        mechanism: ChEMBLClient.Mechanism?,
        indications: [Indication],
        trials trialRecords: [TrialRecord]
    ) async -> Asset? {
        let id = molecule.moleculeChemblId
        let xrefs = (try? await unichem.crossReferences(chemblId: id)) ?? .empty(id)
        let target = await targetRecord(chemblTargetId: mechanism?.targetChemblId)

        // Classify on the halted trial that actually says something, preferring the
        // latest: a sponsor's most recent statement supersedes an older one.
        let statement = trialRecords
            .filter { $0.isHalted && ($0.whyStopped?.isEmpty == false) }
            .max(by: { ($0.deathDate ?? .distantPast) < ($1.deathDate ?? .distantPast) })?
            .whyStopped
        let verdict = await classifier.classify(statement, using: bank)

        // Structures: the exact ligand first, the target as a fallback. Only the best
        // few entries are resolved now; Pocket Reuse loads the rest on demand, because
        // a full entry fetch per PDB id is the single most expensive thing here.
        var structures: [StructureRef] = []
        var hasExactCoCrystal = false
        if let ccd = xrefs.ccdCode,
           let ids = try? await rcsb.entries(containingCCD: ccd, limit: 12), !ids.isEmpty {
            hasExactCoCrystal = true
            structures = await entries(ids, ligandCCD: ccd, resolve: 3)
        }
        var hasAnyTargetStructure = hasExactCoCrystal
        if structures.isEmpty, let accession = target?.uniprotAccession,
           let ids = try? await rcsb.entries(forUniProt: accession, limit: 6), !ids.isEmpty {
            hasAnyTargetStructure = true
            structures = await entries(ids, ligandCCD: nil, resolve: 2)
        }

        let whitespaceResult = whitespace.bestWhitespace(
            associations: target?.associations ?? [],
            failedIndications: indications
        )
        let horizon = scorer.estimatedHorizonYear(
            firstApproval: molecule.firstApproval, trials: trialRecords
        )
        let score = scorer.score(
            cause: verdict.cause,
            hasExactCoCrystal: hasExactCoCrystal,
            hasAnyTargetStructure: hasAnyTargetStructure,
            smallMoleculeLabels: target?.tractabilitySM ?? [],
            whitespace: whitespaceResult.best,
            estimatedHorizonYear: horizon
        )

        return Asset(
            chemblId: id,
            prefName: molecule.prefName,
            synonyms: (molecule.synonyms ?? []).compactMap(\.moleculeSynonym),
            smiles: molecule.structures?.canonicalSmiles,
            inchiKey: molecule.structures?.standardInchiKey,
            maxPhase: molecule.maxPhase,
            withdrawnFlag: molecule.withdrawnFlag == true,
            firstApproval: molecule.firstApproval,
            moleculeType: molecule.moleculeType,
            mechanismOfAction: mechanism?.mechanismOfAction,
            actionType: mechanism?.actionType,
            target: target,
            failedIndications: indications,
            trials: trialRecords,
            ccdCode: xrefs.ccdCode,
            pubchemCID: xrefs.pubchemCID,
            structures: structures,
            verdict: verdict,
            score: score,
            estimatedFTOYear: horizon
        )
    }

    /// Resolve the first `resolve` entries fully; keep the rest as bare identifiers.
    ///
    /// A full entry fetch is one request each, and an asset with twelve co-crystals
    /// would spend twelve of them during ingest to populate a list the user may never
    /// open. Pocket Reuse resolves the remainder on demand.
    private func entries(_ ids: [String], ligandCCD: String?, resolve: Int) async -> [StructureRef] {
        var resolved: [StructureRef] = []
        for id in ids.prefix(resolve) {
            guard let entry = try? await rcsb.entry(id) else { continue }
            resolved.append(StructureRef(
                pdbId: entry.pdbId, title: entry.title, resolution: entry.resolution,
                experimentalMethod: entry.experimentalMethod, releaseDate: entry.releaseDate,
                ligandCCD: ligandCCD, uniprotAccessions: entry.uniprotAccessions
            ))
        }
        // Best resolution first: that is the one worth rendering.
        resolved.sort { ($0.resolution ?? 99) < ($1.resolution ?? 99) }
        let unresolved = ids.dropFirst(resolve).map {
            StructureRef(pdbId: $0, title: "", resolution: nil, experimentalMethod: nil,
                         releaseDate: nil, ligandCCD: ligandCCD, uniprotAccessions: [])
        }
        return resolved + unresolved
    }

    private func hasRecentActivity(_ trials: [TrialRecord], years: Int = 5) -> Bool {
        guard let cutoff = Calendar(identifier: .gregorian).date(byAdding: .year, value: -years, to: Date())
        else { return false }
        return trials.contains { ($0.completionDate ?? $0.startDate ?? .distantPast) > cutoff }
    }

    private func targetRecord(chemblTargetId: String?) async -> TargetRecord? {
        guard let chemblTargetId else { return nil }
        if let cached = targetCache[chemblTargetId] { return cached }

        guard let chemblTarget = try? await chembl.target(id: chemblTargetId) else {
            targetCache[chemblTargetId] = TargetRecord?.none
            return nil
        }
        var ensemblId: String?
        var payload: OpenTargetsClient.TargetPayload?
        if let accession = chemblTarget.uniprotAccession {
            ensemblId = try? await openTargets.ensemblId(forUniProt: accession)
            if let ensemblId { payload = try? await openTargets.target(ensemblId: ensemblId) }
        }

        let associations = (payload?.associatedDiseases?.rows ?? []).compactMap { row -> DiseaseAssociation? in
            guard let disease = row.disease, let did = disease.id, let name = disease.name else { return nil }
            var scores: [String: Double] = [:]
            for s in row.datatypeScores ?? [] {
                if let sid = s.id, let value = s.score { scores[sid] = value }
            }
            return DiseaseAssociation(diseaseId: did, diseaseName: name,
                                      score: row.score ?? 0, datatypeScores: scores)
        }

        let record = TargetRecord(
            chemblId: chemblTargetId,
            prefName: chemblTarget.prefName ?? chemblTargetId,
            targetType: chemblTarget.targetType,
            organism: chemblTarget.organism,
            uniprotAccession: chemblTarget.uniprotAccession,
            ensemblId: ensemblId,
            approvedSymbol: payload?.approvedSymbol,
            targetClasses: (payload?.targetClass ?? []).compactMap(\.label),
            tractabilitySM: payload?.smallMoleculeLabels ?? [],
            safetyLiabilities: (payload?.safetyLiabilities ?? []).map {
                SafetyLiability(event: $0.event, eventId: $0.eventId, datasource: $0.datasource)
            },
            associations: associations
        )
        targetCache[chemblTargetId] = record
        return record
    }
}
