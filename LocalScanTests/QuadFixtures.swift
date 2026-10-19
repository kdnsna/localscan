import CoreGraphics
@testable import LocalScan

enum QuadFixtures {
    static func rect(_ x: CGFloat, _ y: CGFloat,
                     _ width: CGFloat, _ height: CGFloat) -> Quad {
        Quad(topLeft: CGPoint(x: x, y: y),
             topRight: CGPoint(x: x + width, y: y),
             bottomRight: CGPoint(x: x + width, y: y + height),
             bottomLeft: CGPoint(x: x, y: y + height))
    }
}
