import Foundation

struct StereoAnalysis {
    var correlation: Float
    var width: Float
    var points: [SIMD2<Float>]
}

final class StereoAnalyzer {
    private let pointCount: Int

    init(pointCount: Int = DSPConfig.goniometerPoints) {
        self.pointCount = pointCount
    }

    func process(left: UnsafePointer<Float>, right: UnsafePointer<Float>, count: Int) -> StereoAnalysis {
        guard count > 1 else {
            return StereoAnalysis(
                correlation: 1,
                width: 0,
                points: [SIMD2<Float>](repeating: .zero, count: pointCount)
            )
        }

        var sumL: Float = 0
        var sumR: Float = 0
        var sumLL: Float = 0
        var sumRR: Float = 0
        var sumLR: Float = 0
        var sumMid: Float = 0
        var sumSide: Float = 0
        for i in 0..<count {
            let l = left[i]
            let r = right[i]
            sumL += l
            sumR += r
            sumLL += l * l
            sumRR += r * r
            sumLR += l * r
            let mid = (l + r) * 0.5
            let side = (l - r) * 0.5
            sumMid += mid * mid
            sumSide += side * side
        }
        let n = Float(count)
        let cov = sumLR - (sumL * sumR) / n
        let varL = max(sumLL - (sumL * sumL) / n, 0)
        let varR = max(sumRR - (sumR * sumR) / n, 0)

        let correlation: Float
        if varL < 1e-8 || varR < 1e-8 {
            correlation = cov >= 0 ? 1 : -1
        } else {
            correlation = max(-1, min(1, cov / sqrtf(varL * varR)))
        }

        let width = sqrtf(sumSide / max(sumMid + sumSide, 1e-12))

        var points = [SIMD2<Float>](repeating: .zero, count: pointCount)
        let step = max(1, count / pointCount)
        var written = 0
        var i = 0
        while i < count && written < pointCount {
            points[written] = SIMD2(left[i], right[i])
            written += 1
            i += step
        }
        return StereoAnalysis(correlation: correlation, width: width, points: points)
    }
}
