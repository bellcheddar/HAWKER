import SwiftUI

/// The Method sheet, reachable from every tab.
///
/// The plan's requirement is that the classification is never a black box. This
/// prints the whole lexicon, both thresholds, the live class counts, the data sources
/// with their access dates, and the two things that were tried and rejected on
/// measurement. It is the app showing its working.
public struct MethodView: View {
    @Environment(HawkerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                HawkerBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        counts
                        classifier
                        neighbours
                        scoring
                        sources
                        limits
                    }
                    .padding(14)
                }
            }
            .navigationTitle("Method")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var counts: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("What is loaded", subtitle: "Live counts from this device's working set.")
                if let summary = store.summary {
                    row("Molecules considered", "\(summary.considered)")
                    row("Dead assets kept", "\(summary.kept)")
                    row("With a resolved target", "\(summary.withTarget)")
                    row("With a co-crystal of the exact ligand", "\(summary.withCoCrystal)")
                    Divider().overlay(Palette.navy)
                    row("Died of business, not biology",
                        String(format: "%.1f%%", summary.businessFraction * 100),
                        tint: Palette.magenta)
                } else {
                    row("Dead assets loaded", "\(store.assets.count)")
                }
                Divider().overlay(Palette.navy)
                ForEach(CauseOfDeath.allCases, id: \.self) { cause in
                    let n = store.assets.filter { $0.cause == cause }.count
                    if n > 0 {
                        row(cause.label, "\(n)", tint: Palette.colour(for: cause))
                    }
                }
            }
        }
    }

    private var classifier: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(
                    "Cause of death: the lexicon",
                    subtitle: "\(CauseClassifier.stemCount) stems across \(CauseClassifier.lexicon.count) classes, matched case-insensitively in precedence order. First match wins, and its substring is shown as evidence on every asset."
                )
                ForEach(Array(CauseClassifier.lexicon.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: entry.cause.symbolName)
                                .font(.caption2)
                            Text(entry.cause.label)
                                .font(.caption).fontWeight(.semibold)
                            Text("\(entry.stems.count)")
                                .hawkerNumber(Typography.numberSmall)
                                .foregroundStyle(Palette.ghost.opacity(0.6))
                        }
                        .foregroundStyle(Palette.colour(for: entry.cause))
                        Text(entry.stems.joined(separator: " · "))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Palette.ghost.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var neighbours: some View {
        GlassPanel(tint: Palette.violetDeath) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(
                    "Cause of death: the fallback",
                    subtitle: "Text the lexicon does not match goes to a nearest-neighbour vote on the Neural Engine, offline."
                )
                if let seed = ExemplarBank.seedProvenance() {
                    row("Labelled sponsor statements", "\(seed.count)")
                    row("Captured", seed.captured)
                    Text(seed.source)
                        .font(.caption2)
                        .foregroundStyle(Palette.ghost.opacity(0.6))
                }
                row("Neighbours consulted", "\(ExemplarBank.neighbourCount)")
                row("Vote-share gate", String(format: "%.2f", ExemplarBank.voteShareGate))
                Divider().overlay(Palette.navy)
                Text("""
                Measured on a held-out fifth of the labelled statements, this gate answers \
                42.6% of the text it sees at 97.8% precision, and declines the rest. Verdicts \
                from it are marked as inferred everywhere they appear, and their exemplar \
                labels come from the lexicon above, so nothing here is hand curated.
                """)
                .font(.caption)
                .foregroundStyle(Palette.ghost.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(Palette.navy)
                Text("Two approaches were tried and rejected on measurement")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(Palette.amberDeath)
                Text("""
                Eight hand-written prototype sentences with a 0.55 similarity gate classified \
                one held-out sentence in five correctly, and the gate accepted 99.7% of \
                everything including pure noise. Separately, sentence similarity between \
                disease names cannot decide whether two names mean the same disease: \
                "myocardial infarction" and "asthma" score higher together than \
                "atherosclerosis" does with "atherosclerotic disease". Whitespace exclusion \
                therefore uses exact identifiers and a shared-stem rule instead.
                """)
                .font(.caption)
                .foregroundStyle(Palette.ghost.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var scoring: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("The Resurrection Score", subtitle: "A weighted sum of four components and nothing else.")
                ForEach(ResurrectionScore.Kind.allCases, id: \.self) { kind in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(kind.label).font(.caption).fontWeight(.semibold)
                                .foregroundStyle(Palette.ghost)
                            Spacer()
                            Text(String(format: "weight %.2f", kind.weight))
                                .hawkerNumber(Typography.numberSmall)
                                .foregroundStyle(Palette.neon)
                        }
                        Text(kind.explanation)
                            .font(.caption2)
                            .foregroundStyle(Palette.ghost.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var sources: some View {
        GlassPanel(tint: Palette.accent) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Data sources", subtitle: "All public, all keyless, fetched live and cached for seven days.")
                ForEach(Self.dataSources, id: \.name) { source in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(source.name).font(.caption).fontWeight(.semibold)
                            .foregroundStyle(Palette.accent)
                        Text(source.use).font(.caption2)
                            .foregroundStyle(Palette.ghost.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if case .loaded(let date) = store.state {
                    Divider().overlay(Palette.navy)
                    row("Working set built", date.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
    }

    private var limits: some View {
        GlassPanel(tint: Palette.amberDeath) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Stated limits")
                ForEach(Self.knownLimits, id: \.self) { limit in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "circle.fill").font(.system(size: 4)).padding(.top, 6)
                        Text(limit).font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Palette.ghost.opacity(0.85))
                }
            }
        }
    }

    private func row(_ label: String, _ value: String, tint: Color = Palette.neon) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(Palette.ghost.opacity(0.85))
            Spacer(minLength: 8)
            Text(value).hawkerNumber(Typography.numberSmall).foregroundStyle(tint)
        }
    }

    static let dataSources: [(name: String, use: String)] = [
        ("ChEMBL (EMBL-EBI)", "Molecules, max phase, withdrawn flag, mechanism of action, target, and the indications each asset was tested in."),
        ("ClinicalTrials.gov API v2", "Trial status, phase, enrolment, dates, and the sponsor's stated reason for stopping."),
        ("Open Targets Platform", "Target class, small-molecule tractability, safety liabilities, and disease associations with per-datatype evidence scores."),
        ("UniChem (EMBL-EBI)", "Cross-references from a ChEMBL id to the PDB chemical component and the PubChem compound."),
        ("RCSB Protein Data Bank", "Entries containing a given ligand or target, entry metadata, and mmCIF coordinates."),
        ("PubChem PUG-REST", "Ready-made 3D conformers for ligands, so no conformer is generated here."),
        ("openFDA", "Approval dates and application numbers.")
    ]

    static let knownLimits: [String] = [
        "The patent horizon is an estimate from public dates plus \(Scorer.estimatedPatentTermYears) years. It is not a freedom-to-operate opinion.",
        "About 11% of halted trials file no reason at all. Those score an unknown cause, which is weighted neutrally rather than optimistically.",
        "A pocket here is a 5.0 Å shell of residues around the ligand, not a computed cavity. It is fine for comparing reuse, and is not a druggability calculation.",
        "Structures are drawn as tube and licorice. There are no cartoon ribbons in this version.",
        "Trials are joined to compounds through curated cross-references, not by matching drug names, so licensee renames and code names do not cause misses. Compounds ChEMBL has not cross-referenced are simply absent."
    ]
}
