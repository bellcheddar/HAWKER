import SwiftUI
import Charts

/// Tab 2. One asset, in full: the scores, the trial history, the sponsor's own words
/// with the classifier's evidence highlighted, the target, and the 3D pocket.
public struct PostMortemView: View {
    @Environment(HawkerStore.self) private var store
    @Environment(Router.self) private var router
    private let assetId: String

    public init(assetId: String) { self.assetId = assetId }

    private var asset: Asset? { store.asset(id: assetId) }

    public var body: some View {
        ZStack {
            HawkerBackground()
            if let asset {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header(asset)
                        scores(asset)
                        statement(asset)
                        trialHistory(asset)
                        if let target = asset.target { targetCard(asset, target) }
                        structures(asset)
                    }
                    .padding(14)
                }
            } else {
                HawkerEmptyState(
                    symbol: "questionmark.folder",
                    title: "Asset not in the working set",
                    message: "\(assetId) is not among the assets currently loaded. It may not have reached the clinic, or the working set may not have widened this far yet."
                )
            }
        }
        .navigationTitle(asset?.displayName ?? assetId)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: Sections

    private func header(_ asset: Asset) -> some View {
        GlassPanel(tint: Palette.colour(for: asset.cause)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(asset.displayName)
                            .font(Typography.title)
                            .foregroundStyle(.white)
                        Text(asset.chemblId)
                            .hawkerNumber(Typography.numberSmall)
                            .foregroundStyle(Palette.ghost.opacity(0.7))
                        if let moa = asset.mechanismOfAction {
                            Text(moa)
                                .font(.callout)
                                .foregroundStyle(Palette.ghost)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 10)
                    GhostRankRing(rank: asset.ghostRank, size: 68)
                }
                HStack(spacing: 6) {
                    CauseBadge(asset.cause, confidence: asset.verdict.confidence)
                    if let phase = asset.phaseReached { Chip(text: phase.label, colour: Palette.accent) }
                    if asset.withdrawnFlag { Chip(text: "Withdrawn", colour: Palette.hazard, symbol: "xmark.octagon") }
                    if let year = asset.yearOfDeath { Chip(text: "Died \(year)", colour: Palette.slate, symbol: "calendar") }
                }
            }
        }
    }

    private func scores(_ asset: Asset) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    "Resurrection Score",
                    subtitle: "Four components, weighted and shown separately. The total is their weighted sum and nothing else."
                )
                ForEach(asset.score.components) { component in
                    ScoreBar(kind: component.kind, value: component.value)
                }
                if let year = asset.estimatedFTOYear {
                    Divider().overlay(Palette.navy)
                    HStack {
                        Text("Estimated composition-of-matter horizon")
                            .font(.caption)
                            .foregroundStyle(Palette.ghost.opacity(0.8))
                        Spacer()
                        Text(String(year))
                            .hawkerNumber(Typography.numberSmall)
                            .foregroundStyle(asset.ftoLapsedEstimate ? Palette.neon : Palette.ghost)
                    }
                }
            }
        }
    }

    /// The sponsor's verbatim words, with the matched evidence highlighted. This is
    /// what makes the classification auditable rather than a black box.
    @ViewBuilder
    private func statement(_ asset: Asset) -> some View {
        let halted = asset.haltedTrials.filter { $0.whyStopped?.isEmpty == false }
        GlassPanel(tint: Palette.colour(for: asset.cause)) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Why it stopped", subtitle: "The sponsor's own words, as filed.")
                if halted.isEmpty {
                    Text(asset.verdict.confidence == ClassificationConfidence.none
                         ? "No reason was filed with any halted trial. HAWKER scores an unstated reason neutrally rather than optimistically."
                         : "No halted trial carries a statement.")
                        .font(.callout)
                        .foregroundStyle(Palette.ghost.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(halted) { trial in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Text(trial.nctId)
                                    .hawkerNumber(Typography.numberSmall)
                                    .foregroundStyle(Palette.accent)
                                Chip(text: trial.overallStatus.label, colour: Palette.hazard)
                            }
                            highlighted(trial.whyStopped ?? "", evidence: asset.verdict)
                        }
                        .padding(.vertical, 3)
                    }
                    verdictNote(asset.verdict)
                }
            }
        }
    }

    /// Draws the matched substring in the cause colour, inside the full text.
    private func highlighted(_ text: String, evidence: CauseVerdict) -> some View {
        var attributed = AttributedString(text)
        if evidence.confidence == .strong, !evidence.evidence.isEmpty,
           let range = attributed.range(of: evidence.evidence, options: [.caseInsensitive]) {
            attributed[range].foregroundColor = Palette.colour(for: evidence.cause)
            attributed[range].font = .body.bold()
            attributed[range].backgroundColor = Palette.wash(for: evidence.cause)
        }
        return Text(attributed)
            .font(.callout)
            .foregroundStyle(Palette.ghost)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func verdictNote(_ verdict: CauseVerdict) -> some View {
        HStack(spacing: 6) {
            Image(systemName: verdict.confidence == .strong ? "text.magnifyingglass" : "sparkle")
                .font(.caption2)
            Text(noteText(verdict))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Palette.ghost.opacity(0.7))
    }

    private func noteText(_ verdict: CauseVerdict) -> String {
        switch verdict.confidence {
        case .strong:
            "Classified on the highlighted phrase. \(verdict.cause.isMechanistic ? "This is a death by biology." : "This tells us nothing about the molecule.")"
        case .weak:
            "Inferred, not stated: \(verdict.evidence). Inferred verdicts are marked wherever they appear."
        case .none:
            "No stated reason, so the cause is unknown and scored neutrally."
        }
    }

    private func trialHistory(_ asset: Asset) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Trial history", subtitle: "\(asset.trials.count) registered, \(asset.haltedTrials.count) halted.")
                if asset.trials.isEmpty {
                    Text("No trials cross-referenced from ChEMBL for this compound.")
                        .font(.callout)
                        .foregroundStyle(Palette.ghost.opacity(0.7))
                } else {
                    Chart(asset.trials.filter { $0.startDate != nil }) { trial in
                        BarMark(
                            xStart: .value("Start", trial.startDate ?? Date()),
                            xEnd: .value("End", trial.completionDate ?? trial.startDate ?? Date()),
                            y: .value("Trial", trial.nctId)
                        )
                        .foregroundStyle(trial.isHalted ? Palette.hazard : Palette.accent.opacity(0.55))
                        .cornerRadius(3)
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let s = value.as(String.self) {
                                    Text(s).font(.system(size: 9, design: .monospaced))
                                }
                            }
                        }
                    }
                    .frame(height: max(90, Double(asset.trials.count) * 22))
                    .foregroundStyle(Palette.ghost)
                }
            }
        }
    }

    private func targetCard(_ asset: Asset, _ target: TargetRecord) -> some View {
        GlassPanel(tint: Palette.accent) {
            VStack(alignment: .leading, spacing: 10) {
                Button { router.go(.target(target.chemblId)) } label: {
                    SectionHeader(target.displayName, subtitle: target.prefName)
                }
                .buttonStyle(.plain)

                HStack(spacing: 6) {
                    Chip(text: target.family.label, colour: Palette.accent)
                    if let accession = target.uniprotAccession {
                        Chip(text: accession, colour: Palette.neon, symbol: "link")
                    }
                }

                if !target.tractabilitySM.isEmpty {
                    Text("Small-molecule tractability: " + target.tractabilitySM.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(Palette.ghost.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !asset.failedIndications.isEmpty {
                    Text("Failed in")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(Palette.ghost)
                    Text(asset.failedIndications.map(\.term).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(Palette.amberDeath)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let whitespace = asset.whitespaceAssociation {
                    Divider().overlay(Palette.navy)
                    Text("Strongest genetic evidence elsewhere")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(Palette.ghost)
                    HStack {
                        Text(whitespace.diseaseName)
                            .font(.callout)
                            .foregroundStyle(Palette.neon)
                        Spacer()
                        Text(String(format: "%.2f", whitespace.geneticScore))
                            .hawkerNumber(Typography.numberSmall)
                            .foregroundStyle(Palette.neon)
                    }
                }

                if !target.safetyLiabilities.isEmpty {
                    Divider().overlay(Palette.navy)
                    Text("Known safety liabilities: \(target.safetyLiabilities.compactMap(\.event).prefix(4).joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(Palette.hazard.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func structures(_ asset: Asset) -> some View {
        GlassPanel(tint: Palette.neon) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(
                    "Structures",
                    subtitle: asset.hasCoCrystal
                        ? "Co-crystals of this exact ligand (CCD \(asset.ccdCode ?? "-"))."
                        : "No co-crystal of this ligand. Entries below are of the target."
                )
                if asset.structures.isEmpty {
                    Text("No PDB entry found for this ligand or its target.")
                        .font(.callout)
                        .foregroundStyle(Palette.ghost.opacity(0.7))
                } else {
                    ForEach(asset.structures.prefix(8)) { ref in
                        Button {
                            router.go(.pocket(pdbId: ref.pdbId, ccd: asset.ccdCode))
                        } label: {
                            HStack {
                                Text(ref.pdbId)
                                    .hawkerNumber(Typography.numberSmall)
                                    .foregroundStyle(Palette.neon)
                                Text(ref.title.isEmpty ? "Not yet resolved" : ref.title)
                                    .font(.caption)
                                    .foregroundStyle(Palette.ghost.opacity(0.85))
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                Text(ref.resolutionText)
                                    .hawkerNumber(Typography.numberSmall)
                                    .foregroundStyle(Palette.ghost.opacity(0.7))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
