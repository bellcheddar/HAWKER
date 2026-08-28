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
- Grid or spatial hashing for any distance search. No O(n^2) over atoms.
- Instance meshes. One sphere mesh, one cylinder mesh, many transforms.

## Science
- Distances in Angstrom, always labelled. Two to three significant figures.
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
- **Finishing a phase is not a question.** When a phase's acceptance criteria pass:
  commit, push, and start the next phase in the same turn. Do not stop to report and wait
  for "proceed". Pause only for a decision that is genuinely Marc's: a scientific default
  or threshold, a licence, anything destructive or outward-facing, anything needing sudo,
  or the App Store Connect app record.

## Apple
- Team `SYNV8TWB5Z`, bundle ids `com.mdeller.hawker*`. Settled: never ask.
- **Never hard-code the team id.** `project.yml` expands `${APPLE_TEAM_ID}` from
  `credentials.env`, which is gitignored. This repo is public.

## API field notes (probed live 2026-08-28, do not "correct" from memory)
- ChEMBL `max_phase` is a **String** ("3.0"), not a number. So is `max_phase_for_ind`.
- ChEMBL `mechanism.max_phase` **is** an Int. The two disagree; decode accordingly.
- Open Targets `tractability` is `[{label, modality, value: Boolean}]`: booleans, not buckets.
- UniChem `/api/v1/compounds` returns `rcsb_pdb` (CCD), `pubchem` (CID) and every
  `clinicaltrials` NCT id in one call. This removes the plan's name-matching join entirely.
- ClinicalTrials.gov v2: `filter.ids=` takes a comma-separated NCT list; `countTotal=true`
  is required for `totalCount`. `whyStopped` lives in `protocolSection.statusModule`.

## Build notes for this machine (measured, not guessed)
- **Keep DerivedData outside `~/Documents`.** The repo lives in an iCloud-backed folder,
  which continually re-applies Finder metadata, and `codesign` then fails with
  "resource fork, Finder information, or similar detritus not allowed". `xattr -cr`
  fixes it for one build and the daemon undoes it. Build with
  `-derivedDataPath` pointing somewhere outside Documents instead.
- `xcodegen generate` needs `APPLE_TEAM_ID` in the environment: it is expanded into
  `project.yml` and never committed, because this repo is public.
