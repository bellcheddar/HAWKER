# HAWKER: where this got to

Built overnight, 2026-08-28. Live state lives here; the roadmap lives in `README.md`.

## Status

All four phases of `hawker_build_plan_v1.md` are built. Four app targets covering five
platforms build with **zero warnings** under Swift 6 strict concurrency, and **41 tests**
pass. The iOS app was run in a simulator and the macOS app on the desktop, both driving
the real pipeline against live APIs.

```bash
swift test --package-path HawkerKit
export APPLE_TEAM_ID=...   # from credentials.env; never committed, this repo is public
xcodegen generate && open HAWKER.xcodeproj
```

**Build DerivedData outside `~/Documents`.** The repo sits in an iCloud-backed folder
that keeps re-applying Finder metadata, and `codesign` then fails with "resource fork,
Finder information, or similar detritus not allowed". `xattr -cr` fixes it for exactly
one build.

## The one thing that needs you

**Create the App Store Connect app record.** `POST /v1/apps` returns 403 by design: the
App Store name is globally unique and choosing it is not the tooling's job.

A search of the GB App Store finds no app called **HAWKER**, so it is worth trying
first. Note that search cannot see *reserved but unpublished* names, which is the most
likely reason BOFFIN and JUMPjet both ended up with an "ANE" suffix.

Everything downstream is scripted and ready to fire the moment the record exists:

```bash
set -a; source ~/.claude/skills/marcs-vibe-coding/credentials.env; set +a
python3 Tools/asc_api.py status            # confirms the record
python3 Tools/store_metadata.py all        # categories, copy, pricing, rating, EULA
```

Already done: three bundle identifiers registered under team `SYNV8TWB5Z`
(`com.mdeller.hawker`, `.watchkitapp`, `.watchkitapp.widget`); listing copy, categories
(Medical / Reference), keywords, promotional text, review notes and privacy policy all
written and inside Apple's length limits; privacy policy live at
<https://bellcheddar.github.io/HAWKER/privacy.html>.

Two further steps are manual by Apple's design and are described in the skill reference:
**App Privacy** (one form; HAWKER collects nothing) and, for the watch complication, an
**App Group** (created and assigned in the portal, which no API can do).

## What the build plan got wrong, and what replaced it

Each of these was measured before it was changed.

| Plan said | Measurement | Now |
|---|---|---|
| Eight prototype sentences, 0.55 cosine gate, for the classifier fallback | 1 held-out sentence in 5 classified correctly; the gate accepted 99.7% of everything, including `"Study closed."` outscoring four of five clear sentences | k-NN over real sponsor statements labelled by the lexicon. 42.6% coverage at 97.8% precision |
| Sentence similarity to detect a renamed indication | Same-pairs and different-pairs overlap *in the wrong order*: "myocardial infarction"/"asthma" 0.671 against "atherosclerosis"/"atherosclerotic disease" 0.657, and "COPD" against its own expansion 0.287 | Exact identifiers plus a conservative shared-stem rule |
| Reach ClinicalTrials.gov by matching drug names, accepting a miss rate | ChEMBL's `drug_indication.indication_refs` and UniChem both carry NCT ids directly | Join on curated identifiers; the name-matching limitation does not apply |
| SwiftData for the cache | The app reads and writes the whole working set at once and never queries it relationally | One `Codable` JSON snapshot. `Asset` had to be `Codable` for the watch anyway |
| Cold ingest of 2,000 molecules in under 6 minutes | Not reachable at the plan's own politeness limits (see below) | Seeded smaller, widened in the background, which the plan allows |

## Bugs found by running it, not by reading it

- **The keep rule swept in 95% of everything.** "Went quiet" fired for any clinical
  molecule with no trial cross-references, since one with no trials trivially has no
  recent activity: absence of evidence read as evidence of death. Now extracted into
  `KeepRule` with its own 8-case suite.
- **A 166x wasted payload.** ClinicalTrials.gov full study records are about 200 kB and
  the client used roughly 1 kB of each. Field selection took a three-study response from
  593,763 bytes to 3,582.
- **Concurrency was global, not per host.** Open Targets' GraphQL answers in one to two
  seconds and a few of those held every slot while ChEMBL and RCSB queued behind them.
- **Tab labels collided** on an iPhone 17 Pro. Only visible by running it.

## Numbers, and the one that is easy to misread

From a 400-molecule seed: 325 considered, 176 kept, 43.2% with a co-crystal of the exact
ligand, 42.6% with a resolved target.

- **56.2%** of kept assets had **no reason filed at all**. That is a property of the
  corpus: an asset kept because its trials went quiet has no stated reason by
  construction.
- **18.2%** unknown **among assets that do state a reason**. This is the classifier's own
  score, and the only one it is answerable for. The plan's ceiling was 40%.
- **85.7%** of classified assets died of business rather than biology (88.1% at the
  trial level, across the 4,000-study calibration set).

The top of the list is recognisable and the joins are right: Semaxanib/KIT/`2X2M`,
Rimonabant/CNR1/`6AJI`, Alvocidib/CDK2/`1C8K`, Seliciclib/CDK2/`1UNL`,
Marimastat/MMP9/`1R55`.

## Verified by running it, with real data

The simulator's cache was seeded with a completed 176-asset run, so every view was
looked at with data in it rather than in a loading state:

- **The Stall** lists 176 assets with correct science: Semaxanib / KIT / `2X2M` at Ghost
  Rank 95, Reserpine / SLC18A2 / `8UCM` flagged Withdrawn, Oxycodone / OPRM1 / `7U63`.
- **Post Mortem** highlights the classifier's matched phrase inside the sponsor's own
  sentence: "**Administrative**ly complete." picked out in the operational colour, with
  its NCT number and status beside it.
- **The FTO caveat** sits directly beneath its number, in amber, as the plan requires.
- **The Graveyard** headline reads "86% of 63 assets with a stated, classifiable reason",
  with "113 more filed no usable reason and are excluded from this percentage rather than
  assumed either way" immediately below it.

Two bugs only visible this way: the tab labels collided on an iPhone, and the
causes-by-year chart was scaling its axis from zero because Swift Charts treats a bare
Int year as an ordinary continuous value.

Use the DEBUG launch arguments to get back to any of these:

```bash
xcrun simctl launch <udid> com.mdeller.hawker -AppTab graveyard
xcrun simctl launch <udid> com.mdeller.hawker -AppAsset CHEMBL276711
```

## Known soft spot

**Ingest throughput.** A 400-molecule seed takes 14 to 22 minutes wall clock. The limit
is the plan's own politeness settings (five concurrent per host, 200 ms minimum spacing)
against services that are free and publicly funded, so it is a deliberate trade rather
than a defect.

Four runs of identical work took 1183 s, 824 s, 1210 s and 1322 s. I assumed the spread
came from a simulator hitting the same APIs concurrently, then ran one with nothing else
running and got the **slowest** result of the four. So the variance is upstream latency,
not local contention, and no single timing here should be trusted to better than about
40%. The per-host concurrency change is still right on its merits, but the 824 s run does
not demonstrate it.

If a faster cold start matters more than politeness, the levers in order are: drop the
per-host spacing to 100 ms, skip the Open Targets join on the first pass and fill it in
during the background refresh, or seed from ChEMBL's withdrawn set only.
