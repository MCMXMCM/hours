import HoursCore
import XCTest
@testable import Hours

@MainActor
final class HourDialMathTests: XCTestCase {
    func testWheelDragOnlyClaimsHorizontalMovement() {
        XCTAssertTrue(
            HourDialDragIntent.shouldRotateWheel(
                translation: CGSize(width: 80, height: 12)
            )
        )
        XCTAssertFalse(
            HourDialDragIntent.shouldRotateWheel(
                translation: CGSize(width: 12, height: -80)
            )
        )
        XCTAssertFalse(
            HourDialDragIntent.shouldRotateWheel(
                translation: CGSize(width: 40, height: 40)
            )
        )
    }

    func testRefreshPolicyOnlyUsesDisplayLinkWhileActivelySpinning() {
        XCTAssertEqual(
            HourDialRefreshPolicy.animationMinimumInterval,
            1.0 / 120.0
        )
        XCTAssertEqual(
            HourDialRefreshPolicy.resolve(
                isSpinning: true,
                isLive: false,
                isSceneActive: true
            ),
            .displayLink
        )
        XCTAssertEqual(
            HourDialRefreshPolicy.resolve(
                isSpinning: false,
                isLive: true,
                isSceneActive: true
            ),
            .periodic(HourDialRefreshPolicy.liveInterval)
        )
        XCTAssertEqual(
            HourDialRefreshPolicy.resolve(
                isSpinning: false,
                isLive: false,
                isSceneActive: true
            ),
            .stationary
        )
        XCTAssertEqual(
            HourDialRefreshPolicy.resolve(
                isSpinning: true,
                isLive: false,
                isSceneActive: false
            ),
            .stationary
        )
    }

    func testLiveRotationFollowsLocalTwentyFourHourClock() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let midnight = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 23
                )
            )
        )

        XCTAssertEqual(
            HourDialMath.liveRotation(at: midnight, calendar: calendar),
            0,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            HourDialMath.liveRotation(
                at: midnight.addingTimeInterval(3 * 3_600),
                calendar: calendar
            ),
            -45,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            HourDialMath.liveRotation(
                at: midnight.addingTimeInterval(12 * 3_600),
                calendar: calendar
            ),
            -180,
            accuracy: 0.000_1
        )
    }

    func testLiveRotationAdvancesUniformlyAroundSolarDial() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let midnight = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 23
                )
            )
        )
        let threeOhSix = midnight.addingTimeInterval(
            (15 * 60 + 6) * 60
        )

        XCTAssertEqual(
            HourDialMath.liveRotation(
                at: threeOhSix,
                calendar: calendar
            ),
            -226.5,
            accuracy: 0.000_1
        )
    }

    func testLiveRotationStaysInsideCurrentHourUntilItsTimeRangeEnds() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let midnight = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 23
                )
            )
        )
        let fiveMinutesBeforeLaudsEnds = midnight.addingTimeInterval(
            (5 * 60 + 55) * 60
        )
        let primeBegins = midnight.addingTimeInterval(6 * 3_600)

        XCTAssertEqual(
            HourDialMath.liveRotation(
                at: fiveMinutesBeforeLaudsEnds,
                calendar: calendar
            ),
            -88.75,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            HourDialMath.liveRotation(
                at: primeBegins,
                calendar: calendar
            ),
            -90,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            HourDialMath.nearestHour(for: -88.75),
            .lauds
        )
    }

    func testSectorsMatchTheAutomaticHourSchedule() {
        XCTAssertEqual(
            HourDialMath.sectorAngleRange(for: .matins),
            0...60
        )
        XCTAssertEqual(
            HourDialMath.sectorAngleRange(for: .lauds),
            60...90
        )
        XCTAssertEqual(
            HourDialMath.sectorAngleRange(for: .prime),
            90...120
        )
        XCTAssertEqual(
            HourDialMath.sectorAngleRange(for: .sext),
            150...195
        )
        XCTAssertEqual(
            HourDialMath.sectorAngleRange(for: .vespers),
            240...300
        )
        XCTAssertEqual(
            HourDialMath.sectorAngleRange(for: .compline),
            300...360
        )

        let fullDaySpan: Double = OfficeHour.allCases.reduce(0) {
            let range = HourDialMath.sectorAngleRange(for: $1)
            return $0 + range.upperBound - range.lowerBound
        }
        XCTAssertEqual(fullDaySpan, 360, accuracy: 0.000_1)
        XCTAssertEqual(
            HourDialMath.sectorAngleRange(for: .lauds).upperBound
                - HourDialMath.sectorAngleRange(for: .lauds).lowerBound,
            30,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            HourDialMath.sectorAngleRange(for: .matins).upperBound
                - HourDialMath.sectorAngleRange(for: .matins).lowerBound,
            60,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            HourDialMath.sectorAngleRange(for: .vespers).upperBound
                - HourDialMath.sectorAngleRange(for: .vespers).lowerBound,
            60,
            accuracy: 0.000_1
        )

        let orderedHours = [
            OfficeHour.matins, .lauds, .prime, .terce,
            .sext, .none, .vespers, .compline
        ]
        for index in 1..<orderedHours.count {
            let previous = HourDialMath.sectorAngleRange(
                for: orderedHours[index - 1]
            )
            let current = HourDialMath.sectorAngleRange(
                for: orderedHours[index]
            )
            XCTAssertEqual(
                previous.upperBound,
                current.lowerBound,
                accuracy: 0.000_1
            )
        }
        XCTAssertEqual(
            HourDialMath.sectorAngleRange(for: .compline).upperBound,
            HourDialMath.sectorAngleRange(for: .matins).lowerBound + 360,
            accuracy: 0.000_1
        )
    }

    func testRotationWrapsThroughEveryCanonicalHour() {
        XCTAssertEqual(HourDialMath.nearestHour(for: 0), .matins)
        XCTAssertEqual(HourDialMath.nearestHour(for: -58), .matins)
        XCTAssertEqual(HourDialMath.nearestHour(for: -75), .lauds)
        XCTAssertEqual(HourDialMath.nearestHour(for: -130), .terce)
        XCTAssertEqual(HourDialMath.nearestHour(for: -210), .none)
        XCTAssertEqual(HourDialMath.nearestHour(for: -262), .vespers)
        XCTAssertEqual(HourDialMath.nearestHour(for: -330), .compline)
        XCTAssertEqual(HourDialMath.nearestHour(for: 30), .compline)
        XCTAssertEqual(HourDialMath.nearestHour(for: -360), .matins)
    }

    func testTargetRotationUsesShortestEquivalentAngle() {
        XCTAssertEqual(
            HourDialMath.targetRotation(for: .compline, near: 10),
            30,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            HourDialMath.targetRotation(for: .vespers, near: -280),
            -270,
            accuracy: 0.000_1
        )
    }

    func testEveryOfficeTitleAndIconAreCenteredInTheirWedges() {
        for hour in OfficeHour.allCases {
            let range = HourDialMath.sectorAngleRange(for: hour)
            XCTAssertEqual(
                HourDialMath.labelAngle(for: hour),
                (range.lowerBound + range.upperBound) / 2,
                accuracy: 0.000_1
            )
        }
    }

    func testOfficeDetentsAlignTitles() {
        XCTAssertEqual(
            HourDialMath.targetRotation(for: .lauds, near: -75),
            -75,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            HourDialMath.targetRotation(for: .terce, near: -135),
            -135,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            HourDialMath.targetRotation(for: .none, near: -217.5),
            -217.5,
            accuracy: 0.000_1
        )
    }

    func testFlingVelocityIsBoundedAndDeceleratesSmoothly() {
        let velocity = HourDialMath.angularVelocity(
            actual: 40,
            predicted: 1_000,
            diameter: 400
        )
        XCTAssertEqual(velocity, 420, accuracy: 0.000_1)

        let duration = HourDialMath.coastDuration(for: 170)
        XCTAssertEqual(duration, 1, accuracy: 0.000_1)
        XCTAssertEqual(
            HourDialMath.coastRotation(
                start: 0,
                initialVelocity: 170,
                elapsed: duration,
                duration: duration
            ),
            85,
            accuracy: 0.000_1
        )
    }
}
