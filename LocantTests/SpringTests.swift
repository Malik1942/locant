import XCTest
@testable import Locant

final class SpringTests: XCTestCase {
    // 1
    func testStartsAtZeroAndSettlesAtOne() {
        for spring in [Spring.wake, .settle, .tuck] {
            let settle = spring.settleTime(displacement: 1, velocity: 0, tolerance: 0.005)
            XCTAssertEqual(spring.value(at: 0), 0)
            XCTAssertEqual(spring.value(at: settle), 1, accuracy: 0.01)
            XCTAssertEqual(spring.value(at: settle * 2), 1, accuracy: 0.001)
        }
    }

    // 2
    func testUnderDampedOvershootsAndCriticalDoesNot() {
        let samples = stride(from: 0.0, through: 1.0, by: 0.005)
        XCTAssertGreaterThan(samples.map(Spring.wake.value(at:)).max()!, 1.005, "the wake spring overshoots a little")
        let critical = Spring(response: 0.4, damping: 1)
        XCTAssertLessThanOrEqual(samples.map(critical.value(at:)).max()!, 1.0001)
    }

    // 3
    func testProgressIsMonotonicBeforeFirstPeak() {
        let values = stride(from: 0.0, through: 0.2, by: 0.01).map(Spring.wake.value(at:))
        XCTAssertEqual(values, values.sorted())
    }

    // 4
    func testWithoutVelocityTheOffsetIsTodaysCurve() {
        for spring in [Spring.wake, .settle, .tuck] {
            for t in stride(from: 0.0, through: 1.0, by: 0.05) {
                XCTAssertEqual(spring.offset(at: t, displacement: -300, velocity: 0), -300 * (1 - spring.value(at: t)), accuracy: 0.0001)
            }
        }
    }

    // 5
    func testAThrownSpringStartsAtItsVelocityAndStillSettles() {
        let spring = Spring.tuck
        let h = 0.0001
        let start = (spring.offset(at: h, displacement: -300, velocity: 2000) - spring.offset(at: 0, displacement: -300, velocity: 2000)) / h
        XCTAssertEqual(start, 2000, accuracy: 5)
        let settle = spring.settleTime(displacement: -300, velocity: 2000)
        for t in stride(from: settle, through: settle + 1, by: 0.01) {
            XCTAssertLessThanOrEqual(abs(spring.offset(at: t, displacement: -300, velocity: 2000)), 0.25)
        }
    }
}
