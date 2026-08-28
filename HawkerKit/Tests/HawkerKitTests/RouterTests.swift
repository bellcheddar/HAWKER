import Foundation
import Testing
@testable import HawkerKit

@Suite("Routing and deep links")
struct RouterTests {

    @Test("hawker://asset/CHEMBL204021 opens the right Post Mortem")
    func assetDeepLink() throws {
        let url = try #require(URL(string: "hawker://asset/CHEMBL204021"))
        let route = try #require(HawkerRoute(url: url))
        // In a URL of this shape the first component lands in `host`, not `path`,
        // which is the easy way to get this wrong.
        #expect(route == .asset("CHEMBL204021"))
    }

    @Test("Identifiers are upper-cased so a lower-case link still resolves")
    func caseInsensitiveIds() throws {
        let url = try #require(URL(string: "hawker://asset/chembl25"))
        #expect(HawkerRoute(url: url) == .asset("CHEMBL25"))
    }

    @Test("A pocket link carries both the PDB id and the chemical component")
    func pocketDeepLink() throws {
        let url = try #require(URL(string: "hawker://pocket/5i9i/5hv"))
        #expect(HawkerRoute(url: url) == .pocket(pdbId: "5I9I", ccd: "5HV"))

        let bare = try #require(URL(string: "hawker://pocket/5I9I"))
        #expect(HawkerRoute(url: bare) == .pocket(pdbId: "5I9I", ccd: nil))
    }

    @Test("A filtered Stall survives a round trip through its own URL")
    func stallFilterRoundTrip() throws {
        var filter = StallFilter()
        filter.causes = [.businessStrategic, .funding]
        filter.phases = [.phase3]
        filter.families = [.kinase]
        filter.requiresStructure = true
        filter.requiresLapsedFTO = true
        filter.query = "kinase"

        let url = try #require(HawkerRoute.stallFiltered(filter).url)
        let route = try #require(HawkerRoute(url: url))
        guard case .stallFiltered(let restored) = route else {
            Issue.record("expected a filtered Stall, got \(route)")
            return
        }
        #expect(restored.causes == filter.causes)
        #expect(restored.phases == filter.phases)
        #expect(restored.families == filter.families)
        #expect(restored.requiresStructure)
        #expect(restored.requiresLapsedFTO)
        #expect(restored.query == "kinase")
    }

    @Test("Foreign and malformed URLs are rejected rather than guessed at")
    func rejectsJunk() {
        #expect(HawkerRoute(url: URL(string: "https://example.com/asset/CHEMBL25")!) == nil)
        #expect(HawkerRoute(url: URL(string: "hawker://nonsense/thing")!) == nil)
        #expect(HawkerRoute(url: URL(string: "hawker://asset")!) == nil)
    }

    @Test("A filtered Stall switches tab instead of pushing a second Stall")
    @MainActor
    func routerSwitchesTabForStall() throws {
        let router = Router()
        router.tab = .graveyard
        let url = try #require(URL(string: "hawker://stall?cause=businessStrategic"))
        #expect(router.open(url: url))
        // Pushing a Stall on top of the Stall reads as a bug, so the tab changes.
        #expect(router.tab == .stall)
        #expect(router.path.count == 1)
    }

    @Test("The Method sheet is presented, never pushed onto the stack")
    @MainActor
    func methodIsASheet() throws {
        let router = Router()
        router.go(.method)
        #expect(router.presentingMethod)
        #expect(router.path.isEmpty)
    }

    @Test("The filter's summary describes what is being shown")
    func filterSummary() {
        var filter = StallFilter()
        #expect(filter.summary == "All dead assets")
        filter.causes = [.funding]
        filter.requiresStructure = true
        #expect(filter.summary.contains("Funding"))
        #expect(filter.summary.contains("co-crystal"))
    }
}
