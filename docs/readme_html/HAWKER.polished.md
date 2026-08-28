# 🪦 HAWKER

> **Halted Assets, Withdrawn Kinetics, Expired Rights: mining the graveyard of failed clinical assets for reclaimable drugs, reusable pockets and under-exploited targets.**

![swift](https://img.shields.io/badge/swift-6.0-F05138?logo=swift&logoColor=white) ![platforms](https://img.shields.io/badge/platforms-iOS%20%C2%B7%20iPadOS%20%C2%B7%20macOS%20%C2%B7%20visionOS%20%C2%B7%20watchOS-000000?logo=apple&logoColor=white) ![swiftui](https://img.shields.io/badge/SwiftUI-Observable-0071e3?logo=swift&logoColor=white) ![realitykit](https://img.shields.io/badge/RealityKit-3D%20molecular-1C244B) ![charts](https://img.shields.io/badge/Swift%20Charts-analytics-467FF7) ![ane](https://img.shields.io/badge/Neural%20Engine-on--device-B57BFF) ![dependencies](https://img.shields.io/badge/dependencies-zero-00d084) ![tests](https://img.shields.io/badge/tests-41%20passing-00d084) ![data](https://img.shields.io/badge/data-ChEMBL%20%C2%B7%20ClinicalTrials.gov%20%C2%B7%20Open%20Targets%20%C2%B7%20UniChem%20%C2%B7%20RCSB%20%C2%B7%20PubChem%20%C2%B7%20openFDA-467FF7) ![phase](https://img.shields.io/badge/phase-4%20of%204%20built-FFAE43) ![licence](https://img.shields.io/badge/licence-MIT-9b51e0) ![author](https://img.shields.io/badge/author-Marc%20C.%20Deller%2C%20D.Phil.-1C244B)

<table>
<tr>
<td>🌐 <b>Website</b></td><td><a href="https://marcdeller.com" target="_blank" rel="noopener noreferrer">marcdeller.com</a></td>
<td>✉️ <b>Contact</b></td><td><a href="mailto:marc@marcdeller.com">marc@marcdeller.com</a></td>
<td>🐙 <b>GitHub</b></td><td><a href="https://github.com/bellcheddar/HAWKER" target="_blank" rel="noopener noreferrer">bellcheddar/HAWKER</a></td>
</tr>
</table>

---

Thousands of clinical assets are dead. A large fraction died for reasons that had nothing to do with the biology: funding ran out, a trial could not recruit, two companies merged, a portfolio was reshuffled. The compound was fine. The pocket was fine. HAWKER separates **death by biology** from **death by business**, anchors every dead asset onto its 3D structure and pocket, and ranks what deserves a second look.

**Why it matters:** the single most expensive thing in drug discovery is a validated chemical series that nobody is working on, and the reason a programme stopped is usually recorded in public, in the sponsor's own words, in a free-text field almost nobody reads. Of the halted trials HAWKER can classify, **88.1% stopped for reasons that say nothing about the molecule or the target** (measured across 4,000 halted studies; on a 176-asset working set the figure is 85.7%). It is useful for: finding shelved compounds whose composition-of-matter protection has lapsed, spotting targets with strong genetic evidence in an indication they were never tried in, and finding pockets that have been crystallised, dosed into humans and then abandoned with all the SAR precedent still sitting in the PDB.

Everything is pulled live from public APIs. Nothing is hand curated.

## ✨ What it does

Three discovery outputs, each with its own view:

| Output | Question it answers |
|---|---|
| **New drugs** | Which shelved compounds failed non-mechanistically *and* have lapsed protection? |
| **New targets** | Which proteins have strong genetic evidence in an indication the dead asset was never tested in? |
| **New pockets** | Which binding sites were crystallised, drugged into humans, then abandoned? |

## 🧭 The six views

| View | What it is |
|---|---|
| **The Stall** | Every dead asset as a filterable, sortable grid. Filter by cause, phase, target class, structure availability and estimated patent status |
| **Post Mortem** | One asset in full: the four score bars, the trial timeline, the sponsor's verbatim words with the classifier's matched phrase highlighted, the target card, and a live 3D view of the ligand in its pocket |
| **The Graveyard** | The analytics. Causes of death by year, by target class, by phase reached, and Ghost Rank against phase. Every mark drills through to a filtered Stall |
| **Second-hand Shelf** | Assets whose estimated composition-of-matter horizon has passed, with the estimate caveat in the header rather than a footnote |
| **Pocket Reuse** | Target-centric. Every clinical ligand that ever bound a target, superposed into one frame by Kabsch alignment on shared pocket residues, coloured by how each one died, plus a ligand-by-residue contact map |
| **The Overlook** | The whole graveyard as a spatial console: a point cloud (x = year of death, y = structural tractability, z = Ghost Rank, colour = cause, size = phase) with six computed headline findings |

## 🎯 The Resurrection Score

Four components, each 0 to 1, each displayed separately. The total is their weighted sum and nothing else: there is no model here and nothing is fitted.

| Component | Weight | Definition |
|---|---|---|
| **Benign death** | 0.35 | How far the cause of death was a fact about the sponsor rather than about the molecule. Business, funding, operational and enrolment score 1.0; unknown scores 0.5; PK/ADMET 0.15; efficacy 0.05; mechanistic safety 0.0 |
| **Structural tractability** | 0.25 | 0.6 for a co-crystal of the exact ligand, +0.2 for any structure of the target, +0.2 scaled by Open Targets small-molecule tractability |
| **Biological whitespace** | 0.25 | The best genetically supported disease association that is not the indication it failed in |
| **Freedom to operate** | 0.15 | **An estimate only.** Earliest public approval or trial start date plus 20 years |

`overall = Σ weight × component`, rendered 0 to 100 as the **Ghost Rank**.

> ⚠️ **The freedom-to-operate component is a crude estimate from public dates.** Real composition-of-matter expiry needs Orange Book patent listings, term extensions and paediatric exclusivity, none of which are used here. It is not a freedom-to-operate opinion and the app labels it as an estimate everywhere it appears.

## 🩺 How a cause of death is decided

A deterministic lexicon runs first: **285 stems across 7 classes**, matched case-insensitively in precedence order, first match wins. Every classification carries the exact substring that produced it, so the app can show its own working and the Method sheet prints the whole lexicon.

Calibrated against **4,000 real halted studies** pulled from ClinicalTrials.gov, the lexicon brought unknown from 44.5% down to **33.1%** of all halted studies (24.7% of those that state a reason).

### Two numbers that are easy to conflate

On a real 176-asset working set, 64.2% of assets come back `unknown`. That figure is **not** the classifier's score, and reading it as one would be wrong. An asset kept because its trials went quiet has no stated reason *by construction*: no trial was formally terminated, it simply stopped being worked on. The app reports both quantities separately, in the Method sheet and in the headless harness:

| Measured on a 176-asset run | Value |
|---|---|
| Assets where no reason was filed at all | 56.2% of kept |
| **Unknown among assets that do state one** | **18.2%** |
| Died of business rather than biology | 85.7% of classified |

The second row is the one the classifier is answerable for, and it is comfortably inside the 40% ceiling the build plan set.

Text the lexicon does not match falls through to a nearest-neighbour vote on the Neural Engine, offline. Its exemplars are real sponsor statements labelled *by the lexicon*, so nothing is hand curated, and it declines to answer below its confidence gate rather than guessing.

| Vote-share gate | Coverage | Precision |
|---|---|---|
| 0.50 | 68.6% | 89.6% |
| 0.70 | 49.2% | 95.8% |
| **0.80 (shipped)** | **42.6%** | **97.8%** |
| 0.90 | 32.3% | 98.8% |

### Two approaches that were measured and rejected

The build plan specified eight hand-written prototype sentences with a 0.55 cosine gate. Measured against held-out text, the prototypes classified **one sentence in five** correctly, the "PK" prototype acted as an attractor for enrolment, funding and efficacy text alike, and the string `"Study closed."` scored higher than four of five clearly-classifiable sentences. On the rescaled 0–1 similarity, a 0.55 gate accepted **99.7% of everything**, which is the tell that the threshold meant nothing.

Separately, sentence similarity **cannot** decide whether two disease names mean the same disease. Measured pairs:

| Pair | Cosine | Should be |
|---|---|---|
| myocardial infarction / asthma | 0.671 | different |
| atherosclerosis / atherosclerotic disease | 0.657 | same |
| COPD / chronic obstructive pulmonary disease | 0.287 | same |

The distributions overlap completely and in the wrong order, so no threshold separates them. Whitespace exclusion therefore uses exact identifiers plus a conservative shared-stem rule instead.

## 🗄️ Data sources

All free, all keyless, all live, cached on device with a 7-day TTL.

| Source | Gives us |
|---|---|
| **ChEMBL** (EMBL-EBI) | Molecules, max phase, withdrawn flag, mechanism of action, target, and the indications each asset was tested in |
| **ClinicalTrials.gov v2** | Trial status, phase, enrolment, dates, and `whyStopped`, the sponsor's own stated reason |
| **Open Targets** | Target class, small-molecule tractability, safety liabilities, disease associations with per-datatype evidence scores |
| **UniChem** (EMBL-EBI) | ChEMBL id → PDB chemical component (CCD), PubChem CID, and registered NCT ids |
| **RCSB PDB** | Entries containing a ligand or target, entry metadata, mmCIF coordinates |
| **PubChem PUG-REST** | Ready-made 3D conformers, so no conformer generator is needed |
| **openFDA** | Approval dates and application numbers |

### The join

```
ChEMBL molecules at max_phase 2 or 3          (reached the clinic)
  → ChEMBL mechanism + drug_indication, BATCHED via __in filters
  → NCT ids come from indication_refs, so no drug-name matching is needed
  → ClinicalTrials.gov by id, 50 at a time    (statuses, phases, whyStopped)
  → APPLY THE KEEP RULE HERE
  then, for survivors only:
  → UniChem      → CCD code and PubChem CID
  → ChEMBL target → UniProt → Open Targets    (tractability, safety, associations)
  → RCSB         → co-crystals of this exact ligand
keep if: withdrawn, or any trial halted, or clinical with no activity in 5 years
```

The ordering is the whole performance story. A first version called UniChem and both ChEMBL detail endpoints once per molecule, which at this client's 200 ms per-host spacing meant roughly **70 minutes for 2,000 molecules**. Batching the ChEMBL endpoints and deferring everything else until after the keep rule cuts EBI traffic by about 85%, because most molecules are discarded before anything expensive is spent on them.

The build plan expected to reach ClinicalTrials.gov by matching drug names, and listed the miss rate on code names and licensee renames as a known limitation. ChEMBL's `drug_indication.indication_refs` turned out to carry the NCT ids directly, so **the trial join is on curated identifiers and that limitation does not apply**.

## 🧱 Architecture

One local Swift package holds the entire app. The four app targets contain an `App.swift` and nothing else.

```
HAWKER/
├── HawkerKit/                    local SPM package: the whole app
│   └── Sources/HawkerKit/
│       ├── Models/               Asset, TargetRecord, TrialRecord, StructureRef,
│       │                         CauseOfDeath, ResurrectionScore
│       ├── Network/              APIClient actor + 7 API clients
│       ├── Ingest/               IngestPipeline, CauseClassifier
│       ├── Neural/               SentenceSpace, ExemplarBank, WhitespaceMatcher,
│       │                         SemanticSearch
│       ├── Score/                Scorer
│       ├── Structure/            MMCIFParser, SDFParser, PocketFinder, Kabsch,
│       │                         MoleculeGeometry, TubeBuilder, MolecularSceneView
│       ├── Design/               Palette, Typography, Components
│       ├── Router/               HawkerRoute, Router
│       ├── Store/                HawkerStore, AssetCache
│       └── Views/                the six tabs, Method sheet, watch views
├── Apps/HAWKER-{iOS,macOS,visionOS,watchOS}/     App.swift only
└── Tools/                        App Store Connect tooling
```

**Rules:** Swift 6 language mode, strict concurrency, zero warnings, zero third-party dependencies. `@Observable` throughout, no `ObservableObject` and no Combine. Swift Charts for 2D, RealityKit for 3D.

## 🧪 Tests

41 tests, all against **real captured API responses and a real PDB entry**, never hand-written samples.

```bash
swift test --package-path HawkerKit
```

The fixtures earn their keep. Writing decoders against live responses caught, among others:

- ChEMBL's `max_phase` is a **String** (`"3.0"`) on the molecule resource but an **Int** on the mechanism resource
- UniChem's `totalCompounds` is a **String**, and some source ids are Ints where most are Strings
- Open Targets `tractability` is a list of `{label, modality, value: Bool}` **booleans**, not the numbered buckets that were assumed
- RCSB's search service answers **HTTP 204 with an empty body** when nothing matches, not a 200 with an empty result set

Structure tests run against **5I9I** (Lp-PLA2 with darapladib bound, 2.7 Å), which is the exact co-crystal the ingest finds for `CHEMBL204021`, so one real case exercises the whole join. Two of them are deliberately adversarial: the grid-based `PocketFinder` is asserted to return *exactly* what a brute-force O(n²) scan returns, and `Kabsch` is fed a mirror image and asserted **not** to fit it, because without the determinant correction a reflection superposes beautifully and means nothing.

## 🚀 Building

Requires Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/bellcheddar/HAWKER.git
cd HAWKER

# The team id is never committed. Export it, or source your own credentials file.
export APPLE_TEAM_ID=XXXXXXXXXX
xcodegen generate

open HAWKER.xcodeproj
```

There is also a headless run of the ingest, which reports real counts, join hit rates and wall clock without the app:

```bash
swift build --package-path HawkerKit -c release
./HawkerKit/.build/release/hawker-ingest 400                 # report only
./HawkerKit/.build/release/hawker-ingest 400 assets.json     # also export the assets
```

## ✅ To Do

Roadmap for HAWKER, in dependency order. Suggestions welcome.

- [x] **Probe every API before writing a client.** Fetched one live response from each of the seven services and coded the decoders against what actually came back, saving each as a test fixture. Four field-shape assumptions in the build plan turned out to be wrong, and one (`max_phase` as a String) would have silently dropped every asset
- [x] **Deterministic cause-of-death lexicon.** 285 stems across 7 classes with precedence ordering, calibrated on 4,000 real halted studies. Unknown fell from 44.5% to 33.1%. Two first-draft stems were substring collisions and both landed in the most consequential class: `"harm"` matches `"pharmaceutical"`. There is now a collision guard in the test suite
- [x] **Resurrection Score.** Four components, always displayed separately, never collapsed into an unexplained number
- [x] **On-device nearest-neighbour fallback.** Replaced the build plan's hand-written prototype sentences after measuring them at 1-in-5 accuracy. Exemplars are real sponsor statements labelled by the lexicon, so still no hand curation. 42.6% coverage at 97.8% precision, and it declines below its gate
- [x] **Ingest restructured for throughput.** Batched ChEMBL `__in` filters and deferred the expensive per-asset calls until after the keep rule, cutting EBI traffic by about 85%
- [x] **Neon Autopsy design system.** Palette, typography and components, with the cause-of-death colour as a semantic constant that survives into the 3D scene
- [x] **Router and deep links.** Every navigable element routes through one `HawkerRoute` enum; `hawker://asset/CHEMBL204021` opens the right Post Mortem, and a filtered Stall is itself a shareable link
- [x] **Structure stack.** mmCIF `atom_site` parser, V2000 SDF parser, grid-based `PocketFinder`, and a from-scratch Kabsch superposition, all tested against a real entry
- [x] **All six views, on all five platforms.** iOS, iPadOS, macOS, visionOS and watchOS build with zero warnings under Swift 6 strict concurrency
- [x] **Method sheet.** Reachable from every tab, printing the full lexicon, both thresholds, live class counts, data sources, and the two approaches that were rejected on measurement
- [x] **App Store Connect groundwork.** Bundle identifiers registered, listing copy, categories, keywords, review notes and privacy statement prepared and within Apple's length limits
- [x] **App record created** as "HAWKER: Drug Repurposing" (`6806223048`)
- [x] **Full listing pushed** for iOS, macOS and visionOS: categories, description, keywords, promotional text, privacy policy, copyright, free pricing, age rating, content rights, the MIT licence agreement in 175 territories, and App Review contact and notes
- [x] **Builds uploaded and attached**, all three signed Apple Distribution and verified before upload: iOS 4.7 MB, visionOS 2.0 MB, macOS 4.1 MB
- [ ] **App Privacy, then Add for Review.** The one step no API can reach: `appDataUsages` and `appPrivacyDetails` both 404 for a key that can read `/users`. HAWKER collects nothing, so it is one answer
- [x] **Report the right denominator for the unknown rate.** Measuring the classifier against all kept assets conflates "could not tell" with "nobody said". Both figures are now reported separately and the difference is explained where they appear
- [x] **Move PDB entry metadata off the ingest.** Resolving three entries per asset was roughly 500 requests per run, spent on titles for a list most users never open. The RCSB search sorts by resolution server-side, so best-structure-first survives the change at no cost
- [x] **App icon, drawn from the app's own data.** The Overlook's real scatter: 145 assets by estimated horizon year against Ghost Rank, coloured on the cause-of-death scale. Three earlier attempts were thrown away, and what made the difference was checking the data first: `benignDeath` has four distinct values across 176 assets and `structuralTractability` seven, so plotting those draws clumps rather than a cloud. Year has 56. visionOS gets a layered `.solidimagestack` (opaque layer last) and the compiled bundles are checked for the real artefacts, because an empty appiconset still builds
- [ ] **Refine the icon.** It is honest and distinctive but it is a first pass, and an icon is a design decision rather than a generated one
- [x] **DEBUG launch arguments.** `-AppTab`, `-AppAsset`, `-AppPocket`, `-AppMethod`. Without them there is no way to drive the app from a script: a `hawker://` deep link makes the simulator raise a confirmation dialog and `simctl` cannot tap
- [x] **Verified every view against real data**, by seeding the simulator's cache with a completed run. That is how the Graveyard's year axis turned out to be scaling from zero, and how the tab labels turned out to be colliding
- [x] **Screenshots for every platform**, 27 across six display types, all showing real data. Both iPhone slots filled, because App Store Connect dims and locks whichever size it derives from the other. Every capture came back RGBA and needed flattening, and no simulator hands back a size Apple accepts unaltered
- [x] **WatchConnectivity sync.** The phone pushes a top-25 digest whenever its working set changes and the watch adopts it, so the watch's own fetch is the fallback rather than the norm. Scoped to iOS and watchOS: WatchConnectivity imports on visionOS too, but the delegate's required members differ there and a `canImport` guard built a type that failed to conform
- [ ] **Watch complication** showing the day's top reclaimable asset. Blocked on an App Group, which must be created *and* assigned to each bundle id in the portal by hand: the API can enable the capability but its `settings/key` enum has no app-group value
- [x] **The Overlook's idle orbit.** One revolution every 75 seconds, stopping on touch and never starting under Reduce Motion. No shimmer on the data tabs: anything pulsing there reads as noise rather than signal
- [ ] **visionOS ImmersiveSpace polish.** The scene and the "Step inside" entry point exist; hand-driven selection and panel placement at 1.5 m need time on the device
- [ ] **Background refresh** to widen the working set beyond the seeded slice, with a notification when a new high Ghost Rank asset appears
- [ ] **Chemotype clustering** of dead ligands per pocket (Morgan fingerprints, Tanimoto, hierarchical clustering) to spot abandoned series next to successful ones
- [ ] **Pocket similarity search:** find targets whose pockets resemble one where a dead asset already binds, which is a structural repurposing suggestion
- [ ] **Export a Post Mortem as a shareable PDF dossier**

## ⚠️ Stated limits

1. **The patent estimate** is approval or trial start plus 20 years. Real expiry needs Orange Book listings and term extensions. Labelled as an estimate throughout; never presented as legal guidance.
2. **Most kept assets never had a reason filed.** About 11% of *halted studies* leave `whyStopped` blank, but 56% of *kept assets* have no halted trial with a statement at all, because "its trials went quiet" is itself one of the ways in. Those score `unknown`, weighted at 0.5: deliberately neutral rather than optimistic, and excluded from the business-versus-biology percentage rather than assumed either way.
3. **A pocket here is a 5.0 Å ligand-proximity shell**, not a computed cavity. Fine for comparing reuse across entries; not a druggability calculation.
4. **No cartoon ribbons.** Tube and licorice only.
5. **Compounds ChEMBL has not cross-referenced are simply absent.** The join is on curated identifiers, which is more accurate than name matching but not more complete.

## 📄 Licence

MIT. See [LICENCE](LICENCE).

## 👤 Author

**Marc C. Deller, D.Phil.**
[marcdeller.com](https://marcdeller.com) · [marc@marcdeller.com](mailto:marc@marcdeller.com) · [github.com/bellcheddar](https://github.com/bellcheddar)
