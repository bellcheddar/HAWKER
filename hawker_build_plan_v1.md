# HAWKER: 4-Phase Build Plan (v1)

**Halted Assets, Withdrawn Kinetics, Expired Rights**

A multiplatform SwiftUI app that mines the graveyard of failed clinical assets for
reclaimable drugs, reusable pockets and under-exploited targets. Everything is pulled
live from public APIs. Nothing is hand curated.

Author: Marc C. Deller, D.Phil. · Target: one working day (~8 to 9 hours) in Claude Code
Model: `claude-fable-5`

---

## 0. Scope reality check (read this first)

One day for iPhone, iPad, macOS, watchOS and visionOS is achievable **only** because
SwiftUI and RealityKit are genuinely multiplatform and because the plan deliberately
constrains the hard parts:

| Decision | Reason |
|---|---|
| One shared Swift package (`HawkerKit`), five thin app targets | Avoids five codebases |
| RealityKit for all 3D, on iOS, macOS and visionOS | One molecular scene, three presentations |
| watchOS gets data and scores, **no 3D** | Molecular rendering on watch is not worth the hours |
| Ball-and-stick ligands, licorice + tube pockets | Full cartoon ribbons are a day on their own |
| 3D ligand coordinates fetched from PubChem, not generated | No conformer generator to write |
| Deterministic classifier, no ML training | "No hand curation" is a hard requirement |

If the day runs short, ship in this order: iOS, visionOS, macOS, iPadOS (free with iOS),
watchOS last. Phase 4 is explicitly the one to truncate.

---

## 1. What the app does

Thousands of clinical assets are dead. A large fraction died for reasons that had nothing
to do with the biology: funding, enrolment, a merger, a badly chosen endpoint. The compound
was fine. The pocket was fine.

HAWKER separates **death by biology** from **death by business**, anchors every dead asset
onto its 3D structure and pocket, and ranks what deserves a second look.

Three discovery outputs:

1. **New drugs**: shelved compounds whose failure was non-mechanistic and whose composition-
   of-matter protection has lapsed.
2. **New targets**: proteins with strong genetic evidence in an indication that was never
   the one the dead asset was tested in.
3. **New pockets**: binding sites that have been crystallised, drugged into humans, and then
   abandoned, with all the SAR precedent still sitting there.

---

## 2. Platform matrix

| Target | Deployment | Notes |
|---|---|---|
| iOS / iPadOS | 18.0 | `TabView`, `NavigationStack`, `RealityView` |
| macOS | 15.0 | `NavigationSplitView` instead of tabs, same views |
| visionOS | 2.0 | Volumetric window + `ImmersiveSpace` for tab 6 |
| watchOS | 11.0 | List of top assets, scores, cause-of-death chips, no 3D |

Single Xcode project `HAWKER.xcodeproj`, five targets, one local SPM package `HawkerKit`
holding **all** models, networking, parsing, scoring and rendering. App targets contain
only the entry point and platform-specific scene construction.

---

## 3. Architecture

```
HAWKER/
├── HawkerKit/                      (local SPM package, the entire app)
│   ├── Sources/HawkerKit/
│   │   ├── Models/
│   │   │   ├── Asset.swift             dead clinical asset (the core record)
│   │   │   ├── TargetRecord.swift      protein target + tractability + safety
│   │   │   ├── TrialRecord.swift       trial, status, whyStopped, dates
│   │   │   ├── StructureRef.swift      PDB entry, CCD code, chain, pocket residues
│   │   │   ├── CauseOfDeath.swift      enum + confidence + evidence string
│   │   │   └── ResurrectionScore.swift four components, no black box
│   │   ├── Network/
│   │   │   ├── APIClient.swift         actor, async/await, throttled, cached
│   │   │   ├── ChEMBLClient.swift
│   │   │   ├── ClinicalTrialsClient.swift
│   │   │   ├── OpenTargetsClient.swift GraphQL
│   │   │   ├── RCSBClient.swift        search + data + coordinate download
│   │   │   ├── UniChemClient.swift     ChEMBL id to PDB chemical component id
│   │   │   └── PubChemClient.swift     3D SDF conformers
│   │   ├── Ingest/
│   │   │   ├── IngestPipeline.swift    orchestrates the joins
│   │   │   └── CauseClassifier.swift   deterministic lexicon cascade + NL fallback
│   │   ├── Score/
│   │   │   └── Scorer.swift
│   │   ├── Structure/
│   │   │   ├── MMCIFParser.swift       minimal atom_site parser
│   │   │   ├── SDFParser.swift         PubChem 3D conformer parser
│   │   │   ├── PocketFinder.swift      residues within 5.0 Å of the ligand
│   │   │   ├── MoleculeGeometry.swift  atoms and bonds to RealityKit meshes
│   │   │   ├── TubeBuilder.swift       Catmull-Rom spline through CA atoms
│   │   │   └── MolecularSceneView.swift shared RealityView
│   │   ├── Design/
│   │   │   ├── Palette.swift           Neon Autopsy colours
│   │   │   ├── Typography.swift
│   │   │   └── Components.swift        GlassPanel, NeonChip, ScoreBar, etc.
│   │   ├── Router/
│   │   │   ├── HawkerRoute.swift       enum, Hashable, Codable
│   │   │   └── Router.swift            @Observable, NavigationPath, deep links
│   │   ├── Store/
│   │   │   ├── HawkerStore.swift       @Observable app state
│   │   │   └── CacheModels.swift       SwiftData @Model mirrors
│   │   └── Views/
│   │       ├── StallView.swift             tab 1
│   │       ├── PostMortemView.swift        tab 2
│   │       ├── GraveyardView.swift         tab 3
│   │       ├── SecondHandShelfView.swift   tab 4
│   │       ├── PocketReuseView.swift       tab 5
│   │       └── OverlookView.swift          tab 6
├── HAWKER-iOS/          (App.swift only)
├── HAWKER-macOS/
├── HAWKER-visionOS/     (App.swift + ImmersiveSpace scene)
└── HAWKER-watchOS/
```

**Rules**: Swift 6 language mode, strict concurrency, `@Observable` (not
`ObservableObject`), SwiftData for the cache, Swift Charts for analytics, RealityKit for
3D. **Zero third-party dependencies.**

---

## 4. Data layer

All free, all keyless, all live. Cached in SwiftData with a 7-day TTL so the app opens
instantly on the second launch and works offline.

| Source | Endpoint | Gives us |
|---|---|---|
| ChEMBL | `https://www.ebi.ac.uk/chembl/api/data/` | `molecule` (max_phase, withdrawn_flag, withdrawn_reason, SMILES, first_approval), `drug_indication`, `mechanism`, `target` |
| ClinicalTrials.gov v2 | `https://clinicaltrials.gov/api/v2/studies` | terminated/withdrawn/suspended studies, **`whyStopped`** free text, phase, enrolment, sponsor, dates |
| Open Targets | `https://api.platform.opentargets.org/api/v4/graphql` | target tractability buckets, `safetyLiabilities`, disease associations with datatype scores (genetic evidence) |
| UniChem | `https://www.ebi.ac.uk/unichem/` | ChEMBL molecule id to PDB chemical component (CCD) id |
| RCSB Search | `https://search.rcsb.org/rcsbsearch/v2/query` | PDB entries containing a given CCD or UniProt target |
| RCSB Data | `https://data.rcsb.org/rest/v1/core/` | entry metadata, resolution, polymer entity, UniProt mapping |
| RCSB Files | `https://files.rcsb.org/download/{PDBID}.cif` | coordinates |
| PubChem PUG-REST | `https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/` | `SDF?record_type=3d`, ready-made 3D conformers |
| openFDA | `https://api.fda.gov/drug/drugsfda.json` | approval dates, application numbers |

**Hard instruction for Claude Code**: do not trust remembered field names for any of these
APIs. Before writing a client, fetch one live example response (or the GraphQL
introspection for Open Targets) and code against what actually comes back.

**Politeness**: single shared `APIClient` actor, maximum 5 concurrent requests, 200 ms
minimum spacing per host, exponential backoff on 429/503, `URLCache` on disk, descriptive
`User-Agent` including a contact address.

### The join

```
ChEMBL molecules with max_phase >= 2            (reached the clinic)
  → mechanism + target  →  UniProt accession
  → Open Targets by Ensembl id                  (tractability, safety, other diseases)
  → UniChem  →  CCD code  →  RCSB search        (co-crystals of this exact ligand)
  → ClinicalTrials.gov by intervention name     (trials, statuses, whyStopped)
  → keep the asset if: withdrawn_flag == true
                    OR any trial terminated/withdrawn/suspended
                    OR max_phase >= 2 and no approval and no trial activity in 5 years
```

Target roughly 2,000 to 5,000 assets in the working set. Seed the first run with a bounded
slice (ChEMBL `max_phase=2` and `max_phase=3`, first 2,000) so Phase 1 finishes in minutes,
then let a background refresh widen it.

---

## 5. Cause-of-death classifier (no hand curation)

A deterministic, inspectable cascade over the `whyStopped` string plus structured fields.
Ordered precedence, first match wins, every classification carries the matched evidence
substring so the user can audit it in the UI.

| Class | Colour | Triggers (case-insensitive stems) |
|---|---|---|
| `safetyMechanistic` | hazard red | hepatotox, cardiotox, QT, adverse event, DSMB, toxicity, death, serious AE, safety signal |
| `efficacyFutility` | deep amber | futility, lack of efficacy, did not meet, failed primary, interim analysis |
| `pkAdmet` | violet | pharmacokinetic, exposure, bioavailability, half-life, formulation, solubility |
| `enrolment` | teal | enrolment, enrollment, accrual, recruitment, slow, insufficient participants |
| `businessStrategic` | magenta | business decision, strategic, portfolio, prioriti, sponsor decision, merger, acquisition, licensing |
| `funding` | magenta | funding, financial, budget, resources, sponsor closed |
| `operational` | grey | investigator, site, supply, PI left, administrative, COVID, pandemic, regulatory hold on paperwork |
| `unknown` | grey | empty or unmatched |

**Fallback for unmatched text (still no curation):** Apple's `NLEmbedding.sentenceEmbedding`
computes cosine distance from the free text to eight fixed prototype sentences, one per
class, written in code. Above a 0.55 similarity threshold the class is assigned with
`confidence = .weak`. Below it, `unknown`. This runs on the Neural Engine, offline.

Every asset exposes `deathIsMechanistic: Bool` = class in
`{safetyMechanistic, efficacyFutility, pkAdmet}`. That single boolean is the intellectual
spine of the app.

A **Method** sheet in the app prints the full lexicon, the thresholds and the counts per
class, so the classification is never a black box.

---

## 6. Resurrection Score

Four components, each 0 to 1, each displayed separately as a bar, never collapsed into an
unexplained number.

| Component | Weight | Definition |
|---|---|---|
| **Benign death** | 0.35 | 1.0 for business/funding/operational/enrolment deaths, 0.5 for unknown, 0.15 for pkAdmet, 0.05 for efficacy, 0.0 for mechanistic safety |
| **Structural tractability** | 0.25 | 0.6 base if a co-crystal of the exact ligand exists, +0.2 if any PDB entry for the target, +0.2 scaled by Open Targets small-molecule tractability bucket |
| **Biological whitespace** | 0.25 | Best Open Targets association score for a disease **other than** the failed indication, weighted by genetic-evidence datatype score |
| **Freedom to operate (estimate)** | 0.15 | Years elapsed since first patent-eligible date, using earliest ChEMBL/openFDA date + 20 years as an estimated composition-of-matter horizon |

`overall = Σ weight × component`, rendered 0 to 100 as the **Ghost Rank**.

**Guardrail**: the FTO component is a crude estimate from public approval dates and is
labelled as such everywhere it appears. The app must never present it as a
freedom-to-operate opinion. Put that sentence in the UI, not just the code comments.

---

## 7. Design language: "Neon Autopsy"

Minority Report, but legible. Dark, glassy, thin neon strokes, monospaced numerals.

```swift
// Palette.swift
static let void        = Color(hex: 0x05070F)   // background
static let slab        = Color(hex: 0x0E1428)   // panel fill
static let navy        = Color(hex: 0x1C244B)   // brand navy, structural chrome
static let accent      = Color(hex: 0x467FF7)   // brand accent blue
static let neon        = Color(hex: 0x4EF0FF)   // primary neon cyan, glow + highlights
static let ghost       = Color(hex: 0xB6C6E8)   // secondary text
// cause-of-death scale, used identically in every tab and in 3D
static let hazard      = Color(hex: 0xFF4D5E)   // safetyMechanistic
static let amberDeath  = Color(hex: 0xFFAE43)   // efficacyFutility
static let violetDeath = Color(hex: 0xB57BFF)   // pkAdmet
static let tealDeath   = Color(hex: 0x2FE0C0)   // enrolment
static let magenta     = Color(hex: 0xFF5CD8)   // businessStrategic / funding
static let slate       = Color(hex: 0x64748B)   // operational / unknown
```

Rules:
- Typography: SF Pro Display for headings, **SF Mono for every number**, `.monospacedDigit()`
  on anything that animates.
- Panels: `.ultraThinMaterial` over `void`, 1 pt stroke at 35 % neon, 18 pt corner radius,
  soft outer glow via a blurred stroke copy. On visionOS use `.glassBackgroundEffect()`
  instead of material.
- Motion: 0.35 s spring on selection, a slow scanline shimmer on the Overlook only.
  Nothing pulses on the data tabs; that reads as noise, not signal.
- The cause-of-death colour is the app's semantic constant. The same magenta means
  "died of business" in a chart, a chip, a table row and a glowing molecule.
- British English throughout. No em dashes: colons or parentheses instead.
- Accessibility: every colour-coded element also carries a text label or SF Symbol. Support
  Dynamic Type. Respect `accessibilityReduceMotion`.

---

## 8. The six tabs

Every element in every tab is a link. Tapping a bar, a slice, a residue, a chip or a
molecule routes somewhere sensible via the shared `Router`.

### 1. The Stall
Browsable grid of dead assets as glass cards: name, target, phase reached, cause-of-death
chip, Ghost Rank ring, ligand thumbnail (rendered once, cached). Filter bar for cause,
phase, target class, structure availability, FTO status. Sort by any score component.
Search over drug, target and indication.

### 2. Post Mortem
Single asset. Header with the four score bars. Sections: trial history timeline (Swift
Charts, terminated trials marked), the verbatim `whyStopped` text with the matched
classifier evidence highlighted, the target card, the indication it failed in versus the
diseases it has genetic evidence for, and a **live 3D panel** with the ligand and its
pocket. Tapping a pocket residue selects it in 3D and shows its contacts.

### 3. The Graveyard
The analytics view, and the one that makes a figure worth publishing.
- Stacked area: causes of death by year
- Grouped bars: cause of death by target class (kinase, GPCR, protease, ion channel, other)
- Scatter: Ghost Rank vs phase reached, coloured by cause, sized by trial enrolment
- Sankey-style flow (Swift Charts rectangles + custom paths): phase reached → cause of death
- Headline counters: percentage that died of business rather than biology, overall and per
  target class

Everything drills through to a filtered Stall.

### 4. Second-hand Shelf
Only assets whose estimated composition-of-matter horizon has passed. Timeline of estimated
lapse dates, with the estimate caveat in the header. Sorted by Ghost Rank.

### 5. Pocket Reuse
Target-centric. Pick a target: see every ligand that ever reached the clinic against it,
every PDB entry, and a **superposed 3D view** of all co-crystallised ligands in one pocket
frame, coloured by cause of death. This is where an abandoned chemotype next to a
successful one becomes immediately obvious. Includes a residue-contact heatmap
(ligand × pocket residue) built from the parsed structures.

### 6. The Overlook
The showcase. A floating spatial console:
- A 3D point cloud of the entire graveyard: x = year of death, y = structural tractability,
  z = Ghost Rank, colour = cause of death, size = phase reached
- Six glass panels arranged in an arc around it, each carrying one headline finding
  (business-vs-biology split, top reclaimable asset, most reused pocket, biggest whitespace
  target, oldest lapsed asset, deadliest target class)
- Selecting a point pulls its ligand out as a rotating neon ball-and-stick model between
  the panels, with the pocket ghosted behind it
- A slow orbit and a scanline shimmer when idle

Presentation per platform, one scene:
- **visionOS**: volumetric window; a "Step inside" button opens an `ImmersiveSpace` with
  the panels placed around the user and the cloud at arm's length. Hand-driven selection.
- **iOS / iPadOS / macOS**: the same RealityKit scene in a `RealityView` with an orbit
  camera driven by drag and pinch, panels laid out as a 2D glass HUD over it.
- **watchOS**: replaced by a static digest list.

---

## 9. Phase 1 (0:00 to 2:00) — Foundations, data and scoring

**Goal**: a headless, working data engine. No UI beyond a debug list.

**Deliverables**: Xcode project, five targets, `HawkerKit` package, all models, all API
clients, ingest pipeline, classifier, scorer, SwiftData cache.

**Claude Code prompt:**

> Create a new Xcode project called HAWKER at ~/Documents/Vibe_Coding/HAWKER with five app
> targets (iOS 18, macOS 15, visionOS 2, watchOS 11; iPadOS comes free with iOS) and one
> local Swift package HawkerKit containing all logic. Swift 6 language mode, strict
> concurrency, no third-party dependencies.
>
> Build the complete data layer per sections 3, 4, 5 and 6 of hawker_build_plan_v1.md
> (read that file first, in full).
>
> Before writing each API client, fetch one real response with curl and code against the
> actual JSON. For Open Targets, run a GraphQL introspection query first. Do not code from
> remembered field names. Save each sample response under HawkerKit/Tests/Fixtures/ and
> write unit tests that decode the fixtures.
>
> Implement: APIClient actor with 5-concurrent throttling, 200 ms per-host spacing,
> exponential backoff, disk URLCache and a descriptive User-Agent. ChEMBL, ClinicalTrials.gov
> v2, Open Targets GraphQL, UniChem, RCSB search/data, PubChem and openFDA clients.
> IngestPipeline performing the join described in section 4, seeded with the first 2,000
> ChEMBL molecules at max_phase 2 or 3. CauseClassifier as the deterministic lexicon cascade
> in section 5 with the NLEmbedding fallback. Scorer per section 6. SwiftData cache models
> with a 7-day TTL.
>
> Finish with a debug SwiftUI list on iOS showing the top 100 assets by Ghost Rank with
> their cause of death, and a printed summary of counts per class. Do not build any other UI
> yet. Report the actual class distribution you get.

**Acceptance:**
- [ ] `swift test` passes on the fixture decoders
- [ ] Cold ingest of 2,000 molecules completes in under 6 minutes
- [ ] Second launch loads from SwiftData in under 2 seconds
- [ ] The debug list shows sensible assets with sensible causes
- [ ] Class distribution printed and not dominated by `unknown` (if `unknown` exceeds 40 %,
      widen the lexicon before moving on)

---

## 10. Phase 2 (2:00 to 4:30) — Design system, router, tabs 1, 2 and 4

**Goal**: the app is navigable and beautiful on iPhone, iPad and Mac.

**Claude Code prompt:**

> Read hawker_build_plan_v1.md sections 7 and 8. Implement the Neon Autopsy design system in
> HawkerKit/Design: Palette, Typography, and reusable components (GlassPanel, NeonChip,
> ScoreBar, GhostRankRing, CauseBadge, FilterBar, SectionHeader). visionOS uses
> .glassBackgroundEffect(), other platforms use .ultraThinMaterial over the void colour.
>
> Implement Router: a HawkerRoute enum (.asset(id), .target(id), .pocket(pdbId, ccd),
> .stallFiltered(filter), .graveyard(facet)), an @Observable Router holding a NavigationPath,
> and hawker:// deep-link parsing. Every navigable element in the app routes through it.
>
> Build StallView (tab 1), PostMortemView (tab 2) and SecondHandShelfView (tab 4) exactly as
> specified. Leave a placeholder for the 3D panel in PostMortemView; Phase 3 fills it.
>
> Use TabView on iOS/iPadOS and NavigationSplitView with a sidebar on macOS, sharing the same
> view bodies. Handle empty states, loading states and offline states with real messages, not
> spinners on blank screens.
>
> Verify it builds and runs on iPhone, iPad and Mac before reporting done.

**Acceptance:**
- [ ] Builds and runs on all three of iPhone, iPad, Mac
- [ ] Stall filters and sorts without stutter over the full asset set
- [ ] Every chip, card and score bar navigates somewhere
- [ ] A deep link `hawker://asset/CHEMBL25` opens the right Post Mortem
- [ ] Dynamic Type at XXL does not break any layout

---

## 11. Phase 3 (4:30 to 6:30) — Molecular graphics and tabs 3 and 5

**Goal**: real structures, in 3D, everywhere they belong.

**Claude Code prompt:**

> Read hawker_build_plan_v1.md sections 3 and 8. Build the structure stack in
> HawkerKit/Structure:
>
> MMCIFParser: a minimal streaming parser for the atom_site loop only (label_atom_id,
> label_comp_id, label_asym_id, label_seq_id, Cartn_x/y/z, type_symbol, group_PDB). Handle
> multi-line loops and quoted values. Do not attempt full mmCIF.
>
> SDFParser: parse PubChem 3D conformer SDF into atoms and bonds with orders.
>
> PocketFinder: given a HETATM ligand and the polymer atoms, return all residues with any
> atom within 5.0 Å, plus per-residue minimum distance. Use a uniform grid, not an O(n²) scan.
>
> MoleculeGeometry: build RealityKit entities. Ligand as ball and stick (spheres at 0.25 ×
> covalent radius, cylinders for bonds, double bonds as offset pairs), CPK colours with an
> emissive neon rim. Pocket as licorice side chains plus a backbone tube built by TubeBuilder
> (Catmull-Rom spline through CA atoms, circular cross-section extrusion, 8 segments per
> residue). Instance the sphere and cylinder meshes; do not generate a mesh per atom.
> Optional dot surface for the pocket as a low-density point cloud on a 0.8 Å grid.
>
> MolecularSceneView: a shared RealityView with drag-to-rotate, pinch-to-zoom, two-finger
> pan, tap-to-select-atom-or-residue, and a selection binding so SwiftUI lists and the 3D
> scene stay in sync in both directions. On visionOS rely on native manipulation.
>
> Then wire the 3D panel into PostMortemView, and build GraveyardView (tab 3) with Swift
> Charts and PocketReuseView (tab 5) with multi-ligand superposition (align on pocket CA
> atoms by Kabsch superposition; implement Kabsch yourself, it is 40 lines) and the
> ligand × residue contact heatmap.
>
> Target 60 fps with a 3,000-atom pocket on an iPhone. Profile before reporting done.

**Acceptance:**
- [ ] A real PDB entry renders correctly with its ligand in the pocket
- [ ] Kabsch superposition of two co-crystals gives a sane RMSD (validate against a known pair)
- [ ] Tapping a residue in the 3D view highlights it in the list, and vice versa
- [ ] Graveyard charts drill through into a filtered Stall
- [ ] 60 fps sustained on device with a 3,000-atom scene

---

## 12. Phase 4 (6:30 to 8:30) — The Overlook, visionOS, watchOS, ship

**Goal**: the showcase, and the two remaining platforms.

**Claude Code prompt:**

> Read hawker_build_plan_v1.md section 8, tab 6. Build OverlookView as a single RealityKit
> scene with three presentations:
>
> The scene: a point cloud of every asset (x = year of death, y = structural tractability,
> z = Ghost Rank, colour = cause of death, size = phase reached), rendered as instanced
> emissive spheres with additive blending. Six glass panels in an arc, each showing one
> computed headline finding. Selecting a point animates its ligand into the centre as a
> rotating ball-and-stick model with the pocket ghosted behind it, and updates the panels to
> that asset.
>
> visionOS: a volumetric WindowGroup for the console, plus a "Step inside" button opening an
> ImmersiveSpace (.mixed) that places the panels around the user at 1.5 m and the cloud at
> 0.6 m. Panels use .glassBackgroundEffect() and ornaments. Selection by gaze and pinch.
>
> iOS, iPadOS, macOS: the same scene in a RealityView with an orbit camera driven by drag and
> pinch, panels as a 2D glass HUD overlaid. Idle animation: slow orbit plus a scanline
> shimmer, disabled under accessibilityReduceMotion.
>
> Then build the watchOS target: the top 25 assets by Ghost Rank as a list with cause chips
> and score rings, a detail view with the four score bars and the whyStopped text, and a
> complication showing today's top reclaimable asset. Sync via WatchConnectivity from the
> phone's SwiftData cache, with an independent fallback fetch. No 3D on watch.
>
> Finish with a pass over macOS (menu bar commands, keyboard shortcuts, window sizing), an
> app icon placeholder, and a Method sheet reachable from every tab printing the classifier
> lexicon, thresholds, class counts, data sources with access dates, and the FTO estimate
> caveat.

**Acceptance:**
- [ ] The Overlook runs on Vision Pro simulator in both volumetric and immersive modes
- [ ] The same view renders correctly on iPhone and Mac without a separate code path
- [ ] Watch app shows real data and the complication renders
- [ ] Method sheet is reachable from all six tabs
- [ ] The FTO caveat appears wherever an FTO number appears
- [ ] All five targets build clean with zero warnings under Swift 6 strict concurrency

---

## 13. CLAUDE.md for the repository

Drop this at the project root before starting.

```markdown
# HAWKER: working rules

## Identity
Marc C. Deller, D.Phil., structural biologist. Assume deep domain knowledge:
no explanations of what a pocket, a phase 2 trial or a co-crystal is.

## Code
- Swift 6 language mode, strict concurrency, no warnings.
- SwiftUI + @Observable. No ObservableObject, no Combine.
- SwiftData for persistence, Swift Charts for 2D, RealityKit for 3D.
- Zero third-party dependencies. Everything in HawkerKit; app targets hold only App.swift.
- Never code an API against remembered field names: fetch a live response first,
  save it as a test fixture, decode against that.
- Grid or spatial hashing for any distance search. No O(n²) over atoms.
- Instance meshes. One sphere mesh, one cylinder mesh, many transforms.

## Science
- Distances in Å, always labelled. Two to three significant figures.
- Never invent a PDB code, a ChEMBL id, a trial NCT number or a mechanism.
- If an API returns nothing, show an honest empty state. Never fabricate a placeholder record.
- The FTO component is an estimate from public approval dates. Label it as an estimate
  everywhere it is shown. It is not a freedom-to-operate opinion.

## Style
- British English (colour, behaviour, licence, organise, analyse).
- No em dashes. Use colons or parentheses.
- Forbidden words: groundbreaking, revolutionary, paradigm-shifting, game-changing,
  cutting-edge, seamless, delve.
- Comments explain why, not what.

## Workflow
- Work phase by phase against hawker_build_plan_v1.md. Do not start a phase before the
  previous phase's acceptance criteria pass.
- Build and run on device or simulator before reporting a phase complete.
- Report actual numbers (record counts, class distributions, frame rates), not assurances.
```

---

## 14. How to run it

```bash
cd ~/Documents/Vibe_Coding/HAWKER
claude --model claude-fable-5
```

Then, one phase per session, clearing context between phases:

```
> Read hawker_build_plan_v1.md and CLAUDE.md in full. Then execute Phase 1
  (section 9). Stop at the acceptance criteria and report your results against
  each one.
```

Keep the plan file and CLAUDE.md in the repo so every session re-grounds itself. Ask for
a git commit at the end of each phase so a bad Phase 3 does not cost you Phase 2.

---

## 15. Known limits, stated up front

1. **Patent estimate**: approval date plus 20 years is a crude proxy. Real composition-of-
   matter expiry needs Orange Book patent listings and term extensions. Labelled as an
   estimate throughout; never presented as legal guidance.
2. **Drug name matching to ClinicalTrials.gov** is string-based and will miss code names
   (compound numbers, licensee renames). Mitigate with ChEMBL synonyms, accept the miss rate,
   and report the match rate in the Method sheet.
3. **`whyStopped` is sparse**: many terminated trials leave it blank. Those assets score
   `unknown` at 0.5 benign-death, which is deliberately neutral rather than optimistic.
4. **No cartoon ribbons** in v1. Tube plus licorice only.
5. **Pocket definition** is a 5 Å ligand-proximity shell, not a computed cavity. Fine for
   reuse comparison, not a druggability calculation.

---

## 16. Stretch, once it runs

- Chemotype clustering of dead ligands per pocket (Morgan fingerprints in Swift, Tanimoto,
  simple hierarchical clustering) to spot abandoned series next to successful ones
- Pocket similarity search: find targets whose pockets resemble one where a dead asset
  already binds, i.e. a structural repurposing suggestion
- Export a Post Mortem as a shareable PDF dossier
- Weekly background refresh with a notification when a new high Ghost Rank asset appears
- A HAWKER page on marcdeller.com with the Graveyard headline figure

---

Built by Marc C. Deller, D.Phil. · marcdeller.com · marc@marcdeller.com
