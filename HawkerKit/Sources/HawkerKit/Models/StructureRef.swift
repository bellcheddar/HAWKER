import Foundation

/// A PDB entry that contains a given ligand, with enough metadata to rank
/// entries by usefulness before any coordinates are downloaded.
public struct StructureRef: Codable, Sendable, Hashable, Identifiable {
    public var id: String { pdbId }

    public let pdbId: String
    public let title: String
    /// Angstrom. Nil for methods that do not report one (some cryo-EM, NMR).
    public let resolution: Double?
    public let experimentalMethod: String?
    public let releaseDate: Date?
    /// The PDB chemical component id of the ligand of interest in this entry.
    public let ligandCCD: String?
    /// UniProt accessions of the polymer entities, used to confirm the entry
    /// really is the target we think it is.
    public let uniprotAccessions: [String]

    public init(
        pdbId: String,
        title: String,
        resolution: Double?,
        experimentalMethod: String?,
        releaseDate: Date?,
        ligandCCD: String?,
        uniprotAccessions: [String]
    ) {
        self.pdbId = pdbId
        self.title = title
        self.resolution = resolution
        self.experimentalMethod = experimentalMethod
        self.releaseDate = releaseDate
        self.ligandCCD = ligandCCD
        self.uniprotAccessions = uniprotAccessions
    }

    public var coordinateURL: URL? {
        URL(string: "https://files.rcsb.org/download/\(pdbId.uppercased()).cif")
    }

    /// Two significant figures, in Angstrom, or a dash. Never an unlabelled number.
    public var resolutionText: String {
        guard let resolution else { return "-" }
        return String(format: "%.2f Å", resolution)
    }
}

/// A residue lining a ligand-proximity pocket, with its closest approach.
public struct PocketResidue: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(chainId).\(seqId).\(compId)" }

    public let chainId: String
    public let seqId: Int
    public let compId: String
    /// Angstrom, minimum over all atom pairs between this residue and the ligand.
    public let minDistance: Double
    /// Number of this residue's atoms within the cutoff.
    public let contactCount: Int

    public init(chainId: String, seqId: Int, compId: String, minDistance: Double, contactCount: Int) {
        self.chainId = chainId
        self.seqId = seqId
        self.compId = compId
        self.minDistance = minDistance
        self.contactCount = contactCount
    }

    /// One-letter code where the residue is a standard amino acid, else the
    /// three-letter component id.
    public var displayName: String {
        Self.oneLetter[compId].map { "\($0)\(seqId)" } ?? "\(compId)\(seqId)"
    }

    public var distanceText: String { String(format: "%.2f Å", minDistance) }

    static let oneLetter: [String: String] = [
        "ALA": "A", "ARG": "R", "ASN": "N", "ASP": "D", "CYS": "C",
        "GLN": "Q", "GLU": "E", "GLY": "G", "HIS": "H", "ILE": "I",
        "LEU": "L", "LYS": "K", "MET": "M", "PHE": "F", "PRO": "P",
        "SER": "S", "THR": "T", "TRP": "W", "TYR": "Y", "VAL": "V",
        "SEC": "U", "PYL": "O", "MSE": "M"
    ]
}
