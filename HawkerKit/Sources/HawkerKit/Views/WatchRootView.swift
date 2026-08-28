import SwiftUI

/// watchOS. The top assets by Ghost Rank, their cause chips and score rings.
///
/// No 3D and no charts: a wrist is for "which of these is worth opening on the phone",
/// and anything more is a worse version of the phone app.
public struct WatchRootView: View {
    @State private var store = HawkerStore()

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                switch store.state {
                case .loading(let progress):
                    VStack(spacing: 8) {
                        ProgressView(value: progress.fraction).tint(Palette.neon)
                        Text(progress.stage)
                            .font(.caption2)
                            .foregroundStyle(Palette.ghost.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                case .failed(let message):
                    ScrollView {
                        VStack(spacing: 6) {
                            Image(systemName: "wifi.exclamationmark")
                                .foregroundStyle(Palette.hazard)
                            Text("Could not load").font(.headline)
                            Text(message).font(.caption2)
                                .foregroundStyle(Palette.ghost.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    }
                case .idle:
                    ProgressView().tint(Palette.neon)
                case .loaded:
                    list
                }
            }
            .navigationTitle("HAWKER")
            #if os(watchOS)
            .containerBackground(Palette.void.gradient, for: .navigation)
            #endif
        }
        .tint(Palette.neon)
        .task { store.load(limit: 400) }
    }

    private var top: [Asset] { Array(store.assets.prefix(25)) }

    @ViewBuilder
    private var list: some View {
        if top.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "iphone.badge.exclamationmark")
                    .foregroundStyle(Palette.ghost)
                Text("Waiting for iPhone")
                    .font(.headline)
                Text("Open HAWKER on your iPhone to build the working set.")
                    .font(.caption2)
                    .foregroundStyle(Palette.ghost.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding()
        } else {
            List(top) { asset in
                NavigationLink {
                    WatchAssetView(asset: asset)
                } label: {
                    HStack(spacing: 8) {
                        GhostRankRing(rank: asset.ghostRank, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(asset.displayName)
                                .font(.caption).fontWeight(.medium)
                                .lineLimit(1)
                            HStack(spacing: 3) {
                                Image(systemName: asset.cause.symbolName).font(.system(size: 8))
                                Text(asset.cause.shortLabel).font(.system(size: 9))
                            }
                            .foregroundStyle(Palette.colour(for: asset.cause))
                        }
                    }
                }
            }
        }
    }
}

struct WatchAssetView: View {
    let asset: Asset

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    GhostRankRing(rank: asset.ghostRank, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.displayName).font(.headline).lineLimit(2)
                        if let target = asset.target {
                            Text(target.displayName).font(.caption2)
                                .foregroundStyle(Palette.accent)
                        }
                    }
                }
                CauseBadge(asset.cause, confidence: asset.verdict.confidence, compact: true)

                ForEach(asset.score.components) { component in
                    ScoreBar(kind: component.kind, value: component.value, showCaveat: false)
                }
                // The caveat still has to appear wherever the number does, even here.
                Text(ResurrectionScore.Kind.freedomToOperate.caveat ?? "")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.amberDeath.opacity(0.9))

                if let statement = asset.haltedTrials.compactMap(\.whyStopped).first {
                    Divider()
                    Text("Why it stopped").font(.caption).fontWeight(.semibold)
                    Text(statement).font(.caption2)
                        .foregroundStyle(Palette.ghost)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(asset.displayName)
        #if os(watchOS)
        .containerBackground(Palette.void.gradient, for: .navigation)
        #endif
    }
}
