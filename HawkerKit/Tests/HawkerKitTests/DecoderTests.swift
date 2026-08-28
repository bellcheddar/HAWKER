import Foundation
import Testing
@testable import HawkerKit

@Suite("API decoders, against real captured responses")
struct DecoderTests {

    @Test("ChEMBL molecule page: max_phase arrives as a String, not a number")
    func chemblMolecules() throws {
        let page = try HawkerJSON.decoder.decode(
            ChEMBLClient.MoleculePage.self, from: try Fixture.data("chembl_molecule.json")
        )
        #expect(page.molecules.count == 2)
        #expect(page.pageMeta.totalCount == 1892)

        let darapladib = try #require(page.molecules.first { $0.moleculeChemblId == "CHEMBL204021" })
        #expect(darapladib.prefName == "DARAPLADIB")
        // The whole reason for decodeLenientDouble: this is "3.0" on the wire.
        #expect(darapladib.maxPhase == 3.0)
        #expect(darapladib.withdrawnFlag == false)
        #expect(darapladib.structures?.canonicalSmiles?.isEmpty == false)
    }

    @Test("ChEMBL mechanism: max_phase is an Int here, unlike the molecule resource")
    func chemblMechanism() throws {
        let page = try HawkerJSON.decoder.decode(
            ChEMBLClient.MechanismPage.self, from: try Fixture.data("chembl_mechanism.json")
        )
        let m = try #require(page.mechanisms.first)
        #expect(m.targetChemblId == "CHEMBL3514")
        #expect(m.mechanismOfAction == "LDL-associated phospholipase A2 inhibitor")
        #expect(m.actionType == "INHIBITOR")
        #expect(m.maxPhase == 3.0)
    }

    @Test("ChEMBL indication: NCT ids arrive packed into one comma-separated string")
    func chemblIndication() throws {
        let page = try HawkerJSON.decoder.decode(
            ChEMBLClient.IndicationPage.self, from: try Fixture.data("chembl_indication.json")
        )
        let ind = try #require(page.drugIndications.first)
        #expect(ind.efoId == "EFO:0003914")
        #expect(ind.efoTerm == "atherosclerosis")
        // One ref_id holding sixteen NCT numbers, which is why nctIds splits rather than maps.
        #expect(ind.nctIds.count == 16)
        #expect(ind.nctIds.allSatisfy { $0.hasPrefix("NCT") })
        #expect(ind.nctIds.contains("NCT00268996"))
    }

    @Test("ChEMBL target resolves to a Swiss-Prot accession")
    func chemblTarget() throws {
        let t = try HawkerJSON.decoder.decode(
            ChEMBLClient.Target.self, from: try Fixture.data("chembl_target.json")
        )
        #expect(t.targetChemblId == "CHEMBL3514")
        #expect(t.organism == "Homo sapiens")
        #expect(t.uniprotAccession == "Q13093")
    }

    @Test("UniChem hands over the CCD, the CID and every NCT id in one response")
    func unichem() throws {
        let response = try HawkerJSON.decoder.decode(
            UniChemClient.Response.self, from: try Fixture.data("unichem_compounds.json")
        )
        let sources = try #require(response.compounds?.first?.sources)
        var byName: [String: [String]] = [:]
        for s in sources {
            guard let n = s.shortName, let i = s.compoundId else { continue }
            byName[n, default: []].append(i)
        }
        // These three are the entire reason the pipeline does not need name matching.
        #expect(byName["rcsb_pdb"]?.first == "5HV")
        #expect(byName["pubchem"]?.first == "9939609")
        #expect((byName["clinicaltrials"]?.count ?? 0) >= 14)
        #expect(response.totalCompounds == "1")
        // gtopdb returns its id as an Int, which is why compoundId decodes leniently.
        #expect(byName["gtopdb"]?.first == "6696")
    }

    @Test("Open Targets: tractability is a list of booleans, not numbered buckets")
    func openTargets() throws {
        let response = try HawkerJSON.decoder.decode(
            OpenTargetsClient.TargetResponse.self, from: try Fixture.data("opentargets_target.json")
        )
        let t = try #require(response.data?.target)
        #expect(t.approvedSymbol == "PCSK9")
        #expect(t.smallMoleculeLabels.contains("High-Quality Pocket"))
        #expect(t.smallMoleculeLabels.contains("Structure with Ligand"))

        let rows = try #require(t.associatedDiseases?.rows)
        let top = try #require(rows.first)
        #expect(top.disease?.name == "familial hypercholesterolemia")
        let genetic = top.datatypeScores?.first { $0.id == "genetic_association" }
        #expect((genetic?.score ?? 0) > 0.8)
    }

    @Test("RCSB search and entry: resolution_combined is an array")
    func rcsb() throws {
        let search = try HawkerJSON.decoder.decode(
            RCSBClient.SearchResponse.self, from: try Fixture.data("rcsb_search.json")
        )
        #expect(search.resultSet?.first?.identifier == "5I9I")

        let entry = try HawkerJSON.decoder.decode(
            RCSBClient.EntryPayload.self, from: try Fixture.data("rcsb_entry.json")
        )
        #expect(entry.structBlock?.title.map { $0.contains("Darapladib") } == true)
        #expect(entry.entryInfo?.resolutionCombined?.first == 2.7)
        #expect(entry.exptl?.first?.method == "X-RAY DIFFRACTION")
        let released = try #require(entry.accessionInfo?.initialReleaseDate)
        #expect(RCSBClient.parseDate(released) != nil)
    }

    @Test("ClinicalTrials.gov v2: whyStopped, phases and enrolment map onto TrialRecord")
    func clinicalTrials() throws {
        let page = try HawkerJSON.decoder.decode(
            ClinicalTrialsClient.StudyPage.self, from: try Fixture.data("ctgov_studies.json")
        )
        #expect(page.totalCount == 3) // the live query matched 3; the fixture keeps 2
        let records = page.studies.compactMap(\.trialRecord)
        #expect(records.count == 2)
        let phase2 = try #require(records.first { $0.nctId == "NCT00269048" })
        #expect(phase2.phases == [.phase2])
        #expect(phase2.enrolment == 969)
        #expect(phase2.overallStatus == .completed)
        #expect(phase2.startDate != nil)
        // A completed study is not halted: the filter that keeps assets must not be
        // fooled by a trial simply existing.
        #expect(!phase2.isHalted)
    }

    @Test("Terminated studies carry real whyStopped text")
    func terminatedStudies() throws {
        let page = try HawkerJSON.decoder.decode(
            ClinicalTrialsClient.StudyPage.self, from: try Fixture.data("ctgov_terminated.json")
        )
        let records = page.studies.compactMap(\.trialRecord)
        #expect(records.allSatisfy { $0.isHalted })
        #expect(records.contains { ($0.whyStopped?.isEmpty == false) })
    }
}
