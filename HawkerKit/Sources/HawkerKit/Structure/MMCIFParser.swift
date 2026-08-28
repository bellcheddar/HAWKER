import Foundation
import simd

/// A minimal mmCIF reader: the `atom_site` loop only.
///
/// Deliberately not a general mmCIF parser. It reads the column header of the
/// `atom_site` loop, then maps each row by position, which is the only robust way:
/// the column order is not fixed between entries and depositors do not all write the
/// same subset.
///
/// One trap this avoids, learned the hard way on other projects: never slice the
/// record type out by fixed column (`line[0..<6]`). In mmCIF the fields are
/// whitespace separated and unaligned, so a fixed slice drops every `ATOM` while
/// `HETATM` matches by luck. Split on whitespace.
public struct MMCIFParser: Sendable {

    public struct Atom: Sendable, Hashable {
        public let isHetatm: Bool
        public let serial: Int
        public let element: String
        public let atomName: String
        public let altLoc: String?
        public let compId: String
        public let asymId: String
        public let entityId: String?
        public let seqId: Int?
        public let authSeqId: Int?
        public let authAsymId: String?
        public let position: SIMD3<Float>
        public let occupancy: Float
        public let bFactor: Float

        /// The chain a user would recognise, which is the author's numbering.
        public var chainId: String { authAsymId ?? asymId }
        public var residueNumber: Int { authSeqId ?? seqId ?? 0 }
    }

    public struct Structure: Sendable {
        public let atoms: [Atom]
        public let entryId: String?

        public var polymerAtoms: [Atom] { atoms.filter { !$0.isHetatm } }
        public var hetatmAtoms: [Atom] { atoms.filter(\.isHetatm) }

        /// HETATM groups that are plausibly a ligand: not water, not a common
        /// crystallisation additive, and more than a handful of atoms.
        public func ligandGroups(minimumAtoms: Int = 6) -> [LigandGroup] {
            var groups: [String: [Atom]] = [:]
            for atom in hetatmAtoms where !MMCIFParser.ignoredComponents.contains(atom.compId) {
                groups["\(atom.compId)|\(atom.chainId)|\(atom.residueNumber)", default: []].append(atom)
            }
            return groups.values
                .filter { $0.count >= minimumAtoms }
                .map { LigandGroup(compId: $0[0].compId, chainId: $0[0].chainId,
                                   residueNumber: $0[0].residueNumber, atoms: $0) }
                .sorted { $0.atoms.count > $1.atoms.count }
        }

        public func ligand(ccd: String) -> LigandGroup? {
            ligandGroups(minimumAtoms: 1).first { $0.compId.caseInsensitiveCompare(ccd) == .orderedSame }
        }
    }

    public struct LigandGroup: Sendable, Hashable, Identifiable {
        public var id: String { "\(compId).\(chainId).\(residueNumber)" }
        public let compId: String
        public let chainId: String
        public let residueNumber: Int
        public let atoms: [Atom]

        public var centroid: SIMD3<Float> {
            guard !atoms.isEmpty else { return .zero }
            return atoms.reduce(SIMD3<Float>.zero) { $0 + $1.position } / Float(atoms.count)
        }
    }

    /// Waters, ions and the usual cryoprotectants and buffer components. These are
    /// HETATM but are not what anyone means by "the ligand".
    public static let ignoredComponents: Set<String> = [
        "HOH", "DOD", "WAT", "SO4", "PO4", "GOL", "EDO", "PEG", "PG4", "PGE",
        "MPD", "ACT", "ACY", "FMT", "DMS", "TRS", "MES", "EPE", "IMD", "CIT",
        "NA", "K", "MG", "CA", "ZN", "MN", "FE", "CL", "BR", "IOD", "CD", "NI",
        "CU", "CO", "HG", "CS", "RB", "SR", "BA", "NH4", "AZI", "NO3"
    ]

    public init() {}

    public func parse(_ text: String) -> Structure {
        var atoms: [Atom] = []
        var entryId: String?

        var columns: [String: Int] = [:]
        var inLoop = false
        var readingHeader = false

        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("_entry.id") {
                entryId = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                    .dropFirst().first.map(String.init)
                return
            }

            if trimmed == "loop_" {
                inLoop = true
                readingHeader = false
                columns.removeAll()
                return
            }

            if inLoop, trimmed.hasPrefix("_atom_site.") {
                readingHeader = true
                let key = String(trimmed.dropFirst("_atom_site.".count))
                    .split(separator: " ").first.map(String.init) ?? ""
                columns[key] = columns.count
                return
            }

            // A different loop's header: this is not the one we want.
            if inLoop, trimmed.hasPrefix("_") {
                if !readingHeader { columns.removeAll() }
                return
            }

            guard readingHeader, !columns.isEmpty else { return }

            if trimmed.hasPrefix("#") || trimmed.isEmpty {
                readingHeader = false
                inLoop = false
                return
            }

            // Whitespace-separated, honouring the single-quoted values mmCIF uses for
            // fields containing spaces (atom names like 'C1 A' do occur).
            let fields = Self.tokenise(trimmed)
            guard fields.count >= columns.count else { return }

            func field(_ name: String) -> String? {
                guard let index = columns[name], index < fields.count else { return nil }
                let value = fields[index]
                return (value == "?" || value == ".") ? nil : value
            }

            guard let group = field("group_PDB"),
                  let x = field("Cartn_x").flatMap(Float.init),
                  let y = field("Cartn_y").flatMap(Float.init),
                  let z = field("Cartn_z").flatMap(Float.init),
                  let compId = field("label_comp_id")
            else { return }

            atoms.append(Atom(
                isHetatm: group == "HETATM",
                serial: field("id").flatMap(Int.init) ?? atoms.count,
                element: field("type_symbol") ?? "C",
                atomName: field("label_atom_id") ?? "",
                altLoc: field("label_alt_id"),
                compId: compId,
                asymId: field("label_asym_id") ?? "A",
                entityId: field("label_entity_id"),
                seqId: field("label_seq_id").flatMap(Int.init),
                authSeqId: field("auth_seq_id").flatMap(Int.init),
                authAsymId: field("auth_asym_id"),
                position: SIMD3<Float>(x, y, z),
                occupancy: field("occupancy").flatMap(Float.init) ?? 1,
                bFactor: field("B_iso_or_equiv").flatMap(Float.init) ?? 0
            ))
        }

        // Keep one alternate conformer only: alt locs would otherwise double-count
        // atoms in every distance calculation downstream.
        let filtered = atoms.filter { $0.altLoc == nil || $0.altLoc == "A" }
        return Structure(atoms: filtered, entryId: entryId)
    }

    /// Splits on whitespace but keeps single- and double-quoted values together.
    static func tokenise(_ line: String) -> [String] {
        var out: [String] = []
        var current = ""
        var quote: Character?
        for character in line {
            if let q = quote {
                if character == q { quote = nil; out.append(current); current = "" }
                else { current.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character == " " || character == "\t" {
                if !current.isEmpty { out.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
