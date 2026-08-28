import Foundation
import Testing
@testable import HawkerKit

@Suite("On-device sentence embedding (Neural Engine)")
struct NeuralTests {

    @Test("The embedding model loads and produces normalised vectors")
    func spaceLoads() async throws {
        let space = SentenceSpace()
        guard await space.isAvailable else {
            Issue.record("No English sentence embedding on this platform; skipping")
            return
        }
        let dim = await space.dimension
        #expect(dim > 0)
        let v = try #require(await space.vector(for: "The trial was stopped for futility."))
        #expect(v.count == dim)
        // vector(for:) normalises, so self-similarity must be 1 to floating-point noise.
        let self1 = space.similarity(v, v)
        #expect(abs(self1 - 1.0) < 1e-4)
    }

    @Test("Cache returns an identical vector and does not re-embed")
    func caching() async throws {
        let space = SentenceSpace()
        guard await space.isAvailable else { return }
        let text = "Sponsor withdrew support for the programme."
        let a = try #require(await space.vector(for: text))
        let countAfterFirst = await space.cacheCount
        let b = try #require(await space.vector(for: text))
        let countAfterSecond = await space.cacheCount
        #expect(a == b)
        #expect(countAfterFirst == countAfterSecond)
    }

    @Test("The lexicon always beats the neighbour vote where it fires")
    func lexiconWins() async throws {
        let bank = ExemplarBank(space: SentenceSpace())
        await bank.prepare()
        let classifier = CauseClassifier()
        // Text that names a safety stem explicitly must come back strong, with the
        // sponsor's own substring as evidence, never a prototype sentence.
        let verdict = await classifier.classify(
            "The study was stopped because of hepatotoxicity seen in three patients.",
            using: bank
        )
        #expect(verdict.cause == .safetyMechanistic)
        #expect(verdict.confidence == .strong)
        #expect(verdict.evidence.lowercased().contains("hepatotox"))
        #expect(verdict.similarity == nil)
    }

    @Test("Evidence offsets point at the real substring of the original text")
    func evidenceOffsets() throws {
        let classifier = CauseClassifier()
        let text = "Study closed early: slow accrual at all sites."
        let verdict = classifier.classify(text)
        let range = try #require(verdict.evidenceRange)
        let start = text.index(text.startIndex, offsetBy: range.lowerBound)
        let end = text.index(text.startIndex, offsetBy: range.upperBound)
        // The highlight the UI draws must be exactly the evidence string.
        #expect(String(text[start..<end]) == verdict.evidence)
    }

    @Test("The neighbour bank rescues lexicon misses, at its measured precision")
    func rescueRate() async throws {
        let space = SentenceSpace()
        guard await space.isAvailable else { return }
        let bank = ExemplarBank(space: space)
        let clock = ContinuousClock()
        let prepTime = await clock.measure { await bank.prepare() }
        let bankCount = await bank.count
        #expect(bankCount > 1_000)

        let classifier = CauseClassifier()
        let strings = try HawkerJSON.decoder.decode(
            [String].self, from: try Fixture.data("unmatched_whystopped.json")
        )
        // The fixture predates the final lexicon widening, so a few now match. Only the
        // genuine misses are the fallback's job.
        let misses = strings.filter { classifier.lexiconMatch($0) == nil }

        var rescued = 0
        var byCause: [CauseOfDeath: Int] = [:]
        let elapsed = await clock.measure {
            for s in misses {
                let verdict = await classifier.classify(s, using: bank)
                if verdict.cause != .unknown {
                    rescued += 1
                    byCause[verdict.cause, default: 0] += 1
                    #expect(verdict.confidence == .weak)
                    #expect((verdict.similarity ?? 0) >= ExemplarBank.voteShareGate)
                }
            }
        }
        let pct = 100.0 * Double(rescued) / Double(misses.count)
        print("""

        Exemplar bank: \(bankCount) vectors, prepared in \(prepTime)
        Fallback over \(misses.count) genuine lexicon misses:
          rescued \(rescued) (\(String(format: "%.1f", pct))%) in \(elapsed)
        \(byCause.sorted { $0.value > $1.value }
            .map { "  \($0.key.rawValue): \($0.value)" }.joined(separator: "\n"))
        """)
        // The gate was calibrated to 42.6% coverage on held-out data. A wildly higher
        // rate would mean the gate has stopped meaning anything, which is exactly the
        // failure the hand-written prototypes had.
        #expect(pct < 75.0)
    }

    @Test("Whitespace matcher catches a renamed indication by shared stem")
    func whitespaceStemExclusion() throws {
        let matcher = WhitespaceMatcher()
        let failed = [Indication(efoId: "EFO:0003914", term: "atherosclerosis",
                                 maxPhaseForIndication: 3, nctIds: [])]
        let associations = [
            // Same disease, different id and wording: caught by the shared stem
            // "atheroscler", which the sentence embedding demonstrably could not do.
            DiseaseAssociation(diseaseId: "EFO:9999999", diseaseName: "atherosclerotic disease",
                               score: 0.9, datatypeScores: ["genetic_association": 0.9]),
            // Genuinely different biology: must survive.
            DiseaseAssociation(diseaseId: "EFO:0000249", diseaseName: "Alzheimer disease",
                               score: 0.5, datatypeScores: ["genetic_association": 0.5])
        ]
        let result = matcher.bestWhitespace(associations: associations, failedIndications: failed)
        #expect(result.best?.diseaseName == "Alzheimer disease")
        #expect(result.excluded.contains { $0.reason == .sharedStem })
    }

    @Test("Generic clinical words never trigger a shared-stem exclusion")
    func genericWordsDoNotExclude() throws {
        // "disease" is shared by both names and must not make them the same indication.
        #expect(WhitespaceMatcher.sharedDistinctiveStem("Alzheimer disease", ["heart disease"]) == nil)
        #expect(WhitespaceMatcher.sharedDistinctiveStem("breast carcinoma", ["lung carcinoma"]) == nil)
        // A real shared stem still fires.
        #expect(WhitespaceMatcher.sharedDistinctiveStem("atherosclerotic disease", ["atherosclerosis"]) != nil)
    }

    @Test("Whitespace matcher excludes an exact identifier repeat without embedding")
    func whitespaceExactExclusion() throws {
        let matcher = WhitespaceMatcher()
        let failed = [Indication(efoId: "EFO:0003914", term: "atherosclerosis",
                                 maxPhaseForIndication: 3, nctIds: [])]
        let associations = [
            DiseaseAssociation(diseaseId: "EFO:0003914", diseaseName: "atherosclerosis",
                               score: 0.95, datatypeScores: ["genetic_association": 0.95])
        ]
        let result = matcher.bestWhitespace(associations: associations, failedIndications: failed)
        #expect(result.best == nil)
        #expect(result.excluded.first?.reason == .exactIdentifier)
    }
}
