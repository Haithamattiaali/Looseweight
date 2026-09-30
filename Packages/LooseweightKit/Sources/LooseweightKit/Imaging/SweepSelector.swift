import Foundation

/// One frame from the capture sweep: how sharp it is and where the camera was.
public struct SweepCandidate: Hashable, Sendable {
    public var index: Int
    /// Laplacian variance (see `ImageQuality.laplacianVariance`). Higher is sharper.
    public var sharpness: Double
    /// Camera centre in world metres.
    public var position: Vec3
    /// Unit view direction in world space.
    public var forward: Vec3

    public init(index: Int, sharpness: Double, position: Vec3, forward: Vec3) {
        self.index = index
        self.sharpness = sharpness
        self.position = position
        self.forward = forward
    }
}

/// Picks the extra views worth sending to the analysis from a ~1.5–2 s capture sweep:
/// sharp frames first, then the ones that see the plate from the most different angles.
public enum SweepSelector {
    public static func select(_ candidates: [SweepCandidate], main: SweepCandidate?, count: Int = 2,
                              minimumSharpness: Double = ImageQuality.blurThreshold, minimumSeparationM: Double = 0.04) -> [Int] {
        guard count > 0 else { return [] }
        let sharp = candidates.filter { $0.sharpness >= minimumSharpness }
        var chosen: [SweepCandidate] = []
        var anchors: [SweepCandidate] = main.map { [$0] } ?? []
        func spread(_ c: SweepCandidate) -> Double {
            anchors.map { viewDistance(c, $0) }.min() ?? 1
        }
        var pool = sharp.filter { c in main.map { $0.index != c.index } ?? true }
        while chosen.count < count, !pool.isEmpty {
            // Favour new viewpoints, break ties by sharpness.
            guard let best = pool.max(by: { a, b in
                let sa = spread(a), sb = spread(b)
                if abs(sa - sb) > 1e-6 { return sa < sb }
                return a.sharpness < b.sharpness
            }) else { break }
            if !anchors.isEmpty, spread(best) < minimumSeparationM { break }
            chosen.append(best)
            anchors.append(best)
            pool.removeAll { $0.index == best.index }
        }
        return chosen.map(\.index)
    }

    /// Distance between two viewpoints: camera travel plus the change in viewing angle (10° ≈ 5 cm).
    static func viewDistance(_ a: SweepCandidate, _ b: SweepCandidate) -> Double {
        let travel = (a.position - b.position).length
        let cosine = max(-1, min(1, a.forward.normalized.dot(b.forward.normalized)))
        let angle = acos(cosine) * 180 / .pi
        return travel + angle * 0.005
    }
}
