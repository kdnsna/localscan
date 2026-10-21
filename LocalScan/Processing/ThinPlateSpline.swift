import CoreGraphics
import Foundation

/// 确定性的薄板样条（thin-plate spline）插值。
///
/// 用 TPS 拟合 `controlPoints -> values`：每个控制点给定一个输入坐标和对应输出坐标，
/// 对任意点返回平滑插值结果。实现是纯 CPU 的线性求解，不依赖模型或网络。
///
/// 控制点坐标在内部先按包围盒归一化，再解 `K·w + P·a = v`，避免像素级坐标
/// 让矩阵条件数变差；求出的映射再换算回原坐标。控制点太少、重合或共线时
/// 初始化失败，调用方应回退到平纸输出。
struct ThinPlateSpline {
    private let origin: CGPoint
    private let scale: CGFloat
    private let controlPoints: [CGPoint]
    private let weightsX: [Double]
    private let weightsY: [Double]
    /// 仿射项：[常数, x 系数, y 系数]。
    private let affineX: [Double]
    private let affineY: [Double]

    init?(controlPoints: [CGPoint], values: [CGPoint]) {
        guard controlPoints.count >= 3,
              values.count == controlPoints.count else { return nil }
        guard controlPoints.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              values.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            return nil
        }

        let minX = controlPoints.map(\.x).min() ?? 0
        let maxX = controlPoints.map(\.x).max() ?? 0
        let minY = controlPoints.map(\.y).min() ?? 0
        let maxY = controlPoints.map(\.y).max() ?? 0
        let extent = max(maxX - minX, maxY - minY)
        guard extent.isFinite, extent > 1e-9 else { return nil }

        let origin = CGPoint(x: minX, y: minY)
        let scale = extent
        let normalizedPoints = controlPoints.map {
            CGPoint(x: ($0.x - origin.x) / scale, y: ($0.y - origin.y) / scale)
        }
        let normalizedValues = values.map {
            CGPoint(x: ($0.x - origin.x) / scale, y: ($0.y - origin.y) / scale)
        }

        let count = normalizedPoints.count
        let matrixSize = count + 3
        var matrix = [[Double]](repeating: [Double](repeating: 0, count: matrixSize),
                                count: matrixSize)

        for row in 0..<count {
            for column in 0..<count {
                matrix[row][column] = Self.radialBasis(
                    Self.distance(normalizedPoints[row], normalizedPoints[column]))
            }
            let point = normalizedPoints[row]
            matrix[row][count] = 1
            matrix[row][count + 1] = Double(point.x)
            matrix[row][count + 2] = Double(point.y)
            matrix[count][row] = 1
            matrix[count + 1][row] = Double(point.x)
            matrix[count + 2][row] = Double(point.y)
        }

        var rhsX = [Double](repeating: 0, count: matrixSize)
        var rhsY = [Double](repeating: 0, count: matrixSize)
        for index in 0..<count {
            rhsX[index] = Double(normalizedValues[index].x)
            rhsY[index] = Double(normalizedValues[index].y)
        }

        guard let solutionX = Self.solve(matrix, rhsX),
              let solutionY = Self.solve(matrix, rhsY) else { return nil }

        self.origin = origin
        self.scale = scale
        self.controlPoints = normalizedPoints
        self.weightsX = Array(solutionX[0..<count])
        self.weightsY = Array(solutionY[0..<count])
        self.affineX = Array(solutionX[count..<matrixSize])
        self.affineY = Array(solutionY[count..<matrixSize])
    }

    /// 返回该点的插值坐标；坐标始终有限时结果也有限。
    func map(_ point: CGPoint) -> CGPoint {
        guard point.x.isFinite, point.y.isFinite,
              scale > 0 else { return point }
        let normalized = CGPoint(x: (point.x - origin.x) / scale,
                                 y: (point.y - origin.y) / scale)

        var valueX = affineX[0] + affineX[1] * Double(normalized.x)
            + affineX[2] * Double(normalized.y)
        var valueY = affineY[0] + affineY[1] * Double(normalized.x)
            + affineY[2] * Double(normalized.y)

        for index in controlPoints.indices {
            let control = controlPoints[index]
            let dx = Double(normalized.x - control.x)
            let dy = Double(normalized.y - control.y)
            let basis = Self.radialBasis((dx * dx + dy * dy).squareRoot())
            valueX += weightsX[index] * basis
            valueY += weightsY[index] * basis
        }

        return CGPoint(x: valueX * Double(scale) + Double(origin.x),
                       y: valueY * Double(scale) + Double(origin.y))
    }

    // MARK: - 线性代数

    /// TPS 的核函数 U(r) = r²·log(r)，r = 0 时取 0。
    private static func radialBasis(_ radius: Double) -> Double {
        guard radius > 0 else { return 0 }
        return radius * radius * log(radius)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// 部分主元高斯消元。矩阵奇异时返回 nil，由调用方回退。
    private static func solve(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        let count = rhs.count
        guard count > 0, matrix.count == count,
              matrix.allSatisfy({ $0.count == count }) else { return nil }
        var a = matrix
        var b = rhs

        for column in 0..<count {
            var pivot = column
            var pivotMagnitude = abs(a[column][column])
            if column + 1 < count {
                for row in (column + 1)..<count {
                    let magnitude = abs(a[row][column])
                    if magnitude > pivotMagnitude {
                        pivotMagnitude = magnitude
                        pivot = row
                    }
                }
            }
            guard pivotMagnitude > 1e-12 else { return nil }
            if pivot != column {
                a.swapAt(pivot, column)
                b.swapAt(pivot, column)
            }

            let diagonal = a[column][column]
            if column + 1 < count {
                for row in (column + 1)..<count {
                    let factor = a[row][column] / diagonal
                    guard factor != 0 else { continue }
                    a[row][column] = 0
                    for nextColumn in (column + 1)..<count {
                        a[row][nextColumn] -= factor * a[column][nextColumn]
                    }
                    b[row] -= factor * b[column]
                }
            }
        }

        var result = [Double](repeating: 0, count: count)
        for row in stride(from: count - 1, through: 0, by: -1) {
            var value = b[row]
            if row + 1 < count {
                for column in (row + 1)..<count {
                    value -= a[row][column] * result[column]
                }
            }
            result[row] = value / a[row][row]
        }
        return result
    }
}
