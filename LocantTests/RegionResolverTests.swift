import CoreGraphics
import XCTest
@testable import Locant

final class RegionResolverTests: XCTestCase {
    private func snap(_ role: String, label: String? = nil, id: String? = nil, x: Double, y: Double, w: Double, h: Double) -> ElementSnapshot {
        ElementSnapshot(element: AttributeSet(role: role, description: label, identifier: id, frame: Frame(x: x, y: y, w: w, h: h), childCount: 0), ancestors: [])
    }

    // 1
    func testHalfInsideRule() {
        let region = CGRect(x: 0, y: 0, width: 200, height: 100)
        let kept = RegionResolver.elements(in: region, among: [
            snap("AXButton", label: "full", x: 50, y: 20, w: 100, h: 40),
            snap("AXButton", label: "half", x: 150, y: 20, w: 100, h: 40),
            snap("AXButton", label: "quarter", x: 180, y: 20, w: 100, h: 40),
            snap("AXButton", label: "outside", x: 300, y: 20, w: 100, h: 40),
        ])
        XCTAssertEqual(kept.map(\.label), ["full", "half"])
    }

    // 2
    func testContainersDroppedDuplicatesCollapsedReadingOrderCapped() {
        let region = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        var snaps = [
            snap("AXGroup", label: "card", x: 0, y: 0, w: 900, h: 900),
            snap("AXButton", label: "b-right", x: 500, y: 100, w: 50, h: 20),
            snap("AXButton", label: "b-left", x: 10, y: 100, w: 50, h: 20),
            snap("AXButton", label: "b-left-dup", x: 10, y: 100, w: 50, h: 20),
            snap("AXStaticText", label: "top", x: 10, y: 10, w: 50, h: 20),
        ]
        for i in 0..<12 { snaps.append(snap("AXStaticText", label: "row\(i)", x: 10, y: 200 + Double(i) * 30, w: 50, h: 20)) }
        let kept = RegionResolver.elements(in: region, among: snaps)
        XCTAssertEqual(kept.count, 12)
        XCTAssertEqual(kept.prefix(3).map(\.label), ["top", "b-left", "b-right"])
        XCTAssertFalse(kept.contains { $0.role == "group" })
        XCTAssertEqual(kept.filter { $0.frame == Frame(x: 10, y: 100, w: 50, h: 20) }.count, 1)
    }

    // 3
    func testPrimaryPrefersIdentifierThenLabelNearestCenter() {
        let region = CGRect(x: 0, y: 0, width: 400, height: 200)
        let farID = snap("AXButton", label: "far", id: "farButton", x: 0, y: 0, w: 40, h: 20)
        let nearLabel = snap("AXStaticText", label: "Title", x: 180, y: 90, w: 40, h: 20)
        let nearerID = snap("AXButton", label: "near", id: "nearButton", x: 150, y: 150, w: 40, h: 20)
        XCTAssertEqual(RegionResolver.primary(among: [farID, nearLabel, nearerID], in: region)?.identifier, "nearButton")
        XCTAssertEqual(RegionResolver.primary(among: [nearLabel, snap("AXButton", label: "unlabeled-far", x: 0, y: 0, w: 40, h: 20)], in: region)?.label, "Title")
        XCTAssertNil(RegionResolver.primary(among: [snap("AXImage", x: 10, y: 10, w: 40, h: 40)], in: region))
    }

    // 4
    func testNearbyPicksClosestLabeledWithOffsets() {
        let point = CGPoint(x: 200, y: 450)
        let nodes: [AttributeSet] = [
            AttributeSet(role: "AXButton", description: "Resurfacing", frame: Frame(x: 43, y: 304, w: 370, h: 48), childCount: 0),
            AttributeSet(role: "AXGroup", description: "Tab Bar", frame: Frame(x: 27, y: 972, w: 402, h: 83), childCount: 0),
            AttributeSet(role: "AXStaticText", description: "Ocean", frame: Frame(x: 43, y: 251, w: 103, h: 40), childCount: 0),
            AttributeSet(role: "AXButton", frame: Frame(x: 190, y: 440, w: 20, h: 20), childCount: 0), // unlabeled: excluded
            AttributeSet(role: "AXGroup", frame: Frame(x: 27, y: 181, w: 402, h: 874), childCount: 5),  // unlabeled container: excluded
        ]
        let nearby = RegionResolver.nearby(point: point, among: nodes)
        XCTAssertEqual(nearby.map(\.element.label), ["Resurfacing", "Ocean", "Tab Bar"])
        XCTAssertEqual(nearby.map(\.offset), ["98 pt above", "159 pt above", "522 pt below"])
        XCTAssertEqual(RegionResolver.offsetText(from: CGPoint(x: 10, y: 50), to: CGRect(x: 50, y: 40, width: 20, height: 20)), "40 pt right")
        XCTAssertEqual(RegionResolver.offsetText(from: CGPoint(x: 60, y: 50), to: CGRect(x: 50, y: 40, width: 20, height: 20)), "inside")
    }
}
