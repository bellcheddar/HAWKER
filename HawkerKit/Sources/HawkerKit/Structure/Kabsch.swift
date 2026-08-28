import Foundation
import simd

/// Kabsch superposition: the optimal rigid rotation aligning two equal-length point
/// sets, plus the RMSD it achieves.
///
/// Used by Pocket Reuse to bring every co-crystal of a target into one frame, so that
/// an abandoned chemotype sitting next to a successful one is visible rather than
/// merely adjacent in a list.
public enum Kabsch {

    public struct Alignment: Sendable {
        public let rotation: simd_float3x3
        /// Angstrom.
        public let rmsd: Double
        public let pairCount: Int

        let mobileCentroid: SIMD3<Float>
        let referenceCentroid: SIMD3<Float>

        /// Move a point from the mobile frame into the reference frame.
        public func transform(_ p: SIMD3<Float>) -> SIMD3<Float> {
            rotation * (p - mobileCentroid) + referenceCentroid
        }

        public func transform(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
            points.map(transform)
        }

        /// Two to three significant figures, in Angstrom, always labelled.
        public var rmsdText: String { String(format: "%.2f Å", rmsd) }
    }

    /// `mobile` and `reference` must be the same length and in correspondence.
    public static func superpose(mobile: [SIMD3<Float>], reference: [SIMD3<Float>]) -> Alignment? {
        guard mobile.count == reference.count, mobile.count >= 3 else { return nil }
        let n = Float(mobile.count)

        let mobileCentroid = mobile.reduce(SIMD3<Float>.zero, +) / n
        let referenceCentroid = reference.reduce(SIMD3<Float>.zero, +) / n

        let p = mobile.map { $0 - mobileCentroid }
        let q = reference.map { $0 - referenceCentroid }

        // Covariance H = P^T Q.
        var h = simd_float3x3(0)
        for i in 0..<p.count {
            h.columns.0 += p[i] * q[i].x
            h.columns.1 += p[i] * q[i].y
            h.columns.2 += p[i] * q[i].z
        }

        guard let (u, s, vt) = svd3x3(h) else { return nil }
        _ = s

        // Correct for a reflection: without this the "best fit" can be a mirror image,
        // which superposes beautifully and is chemically meaningless.
        var d = simd_float3x3(1)
        let det = simd_determinant(vt.transpose * u.transpose)
        d.columns.2.z = det < 0 ? -1 : 1
        let rotation = (vt.transpose * d * u.transpose)

        var sum: Double = 0
        for i in 0..<p.count {
            let moved = rotation * p[i]
            sum += Double(simd_distance_squared(moved, q[i]))
        }
        let rmsd = (sum / Double(p.count)).squareRoot()

        return Alignment(
            rotation: rotation,
            rmsd: rmsd,
            pairCount: mobile.count,
            mobileCentroid: mobileCentroid,
            referenceCentroid: referenceCentroid
        )
    }

    /// One-sided Jacobi SVD for a 3x3 matrix. Small, dependency-free and stable enough
    /// for coordinates in Angstrom.
    static func svd3x3(_ a: simd_float3x3) -> (u: simd_float3x3, s: SIMD3<Float>, vt: simd_float3x3)? {
        var u = a
        var v = simd_float3x3(1)

        for _ in 0..<64 {
            var converged = true
            for p in 0..<2 {
                for q in (p + 1)..<3 {
                    let cp = column(u, p), cq = column(u, q)
                    let alpha = simd_dot(cp, cp)
                    let beta = simd_dot(cq, cq)
                    let gamma = simd_dot(cp, cq)
                    if abs(gamma) < 1e-10 * (alpha * beta).squareRoot() { continue }
                    converged = false

                    let zeta = (beta - alpha) / (2 * gamma)
                    let t = (zeta >= 0 ? 1 : -1) / (abs(zeta) + (1 + zeta * zeta).squareRoot())
                    let c = 1 / (1 + t * t).squareRoot()
                    let s = c * t

                    setColumn(&u, p, c * cp - s * cq)
                    setColumn(&u, q, s * cp + c * cq)
                    let vp = column(v, p), vq = column(v, q)
                    setColumn(&v, p, c * vp - s * vq)
                    setColumn(&v, q, s * vp + c * vq)
                }
            }
            if converged { break }
        }

        var singular = SIMD3<Float>.zero
        for i in 0..<3 {
            let c = column(u, i)
            let norm = simd_length(c)
            singular[i] = norm
            if norm > 1e-9 { setColumn(&u, i, c / norm) }
        }
        return (u, singular, v.transpose)
    }

    private static func column(_ m: simd_float3x3, _ i: Int) -> SIMD3<Float> {
        switch i { case 0: m.columns.0; case 1: m.columns.1; default: m.columns.2 }
    }

    private static func setColumn(_ m: inout simd_float3x3, _ i: Int, _ v: SIMD3<Float>) {
        switch i { case 0: m.columns.0 = v; case 1: m.columns.1 = v; default: m.columns.2 = v }
    }
}
