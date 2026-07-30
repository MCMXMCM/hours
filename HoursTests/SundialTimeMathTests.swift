import XCTest
@testable import Hours
import HoursCore

@MainActor
final class SundialTimeMathTests: XCTestCase {
    func testLiveSundialRefreshesEveryFiveMinutes() {
        XCTAssertEqual(SundialRefreshPolicy.liveInterval, 5 * 60)
    }

    func testSelectionChevronOnlySupplementsMissingShadows() {
        for hour in OfficeHour.allCases {
            XCTAssertTrue(
                SundialAffordance.showsSelectionChevron(
                    for: hour,
                    shadowsEnabled: false
                ),
                "Every selected hour needs a chevron in dark mode."
            )
            XCTAssertEqual(
                SundialAffordance.showsSelectionChevron(
                    for: hour,
                    shadowsEnabled: true
                ),
                hour == .matins || hour == .compline,
                "Only shadowless hours need a chevron in light mode."
            )
        }
    }

    func testCanonicalHourRowsKeepTheMockupSpacing() {
        let compactLayout = SundialLayout(
            size: CGSize(
                width: 393,
                height: SundialLayout.minimumHeight
            )
        )
        let hours = OfficeHour.allCases

        for index in 1..<hours.count {
            let previous = compactLayout.labelPosition(
                for: hours[index - 1]
            )
            let current = compactLayout.labelPosition(
                for: hours[index]
            )

            XCTAssertEqual(
                current.y - previous.y,
                SundialLayout.minimumHourRowSpacing,
                accuracy: 0.000_1
            )
        }
    }

    func testCanonicalHourRowsReserveTrailingDisclosureSpace() {
        for width in [320.0, 393.0, 768.0] {
            let layout = SundialLayout(
                size: CGSize(width: width, height: 500)
            )
            let rowCenter = layout.labelPosition(for: .compline)
            let rowTrailingEdge =
                rowCenter.x + SundialLayout.hourRowWidth / 2
            let labelTrailingEdge =
                rowTrailingEdge
                    - SundialLayout.disclosureWidth
                    - SundialLayout.disclosureSpacing

            XCTAssertLessThanOrEqual(
                rowTrailingEdge,
                width - 16,
                "The disclosure chevron should not touch the screen edge."
            )
            XCTAssertEqual(
                rowTrailingEdge - labelTrailingEdge,
                SundialLayout.disclosureWidth
                    + SundialLayout.disclosureSpacing,
                accuracy: 0.000_1,
                "Every hour label should reserve the disclosure column."
            )
        }
    }

    func testCanonicalBoundariesMatchTheReferenceShadowPositions() {
        let cases: [
            (
                seconds: Double,
                angle: Double,
                length: Double,
                verticalProgress: Double
            )
        ] = [
            (0, -90, 0, 0),
            (3 * 3_600, -90, 1, 1.0 / 7.0),
            (6 * 3_600, -60, 1, 2.0 / 7.0),
            (9 * 3_600, -30, 1, 3.0 / 7.0),
            (12 * 3_600, 0, 1, 4.0 / 7.0),
            (15 * 3_600, 30, 1, 5.0 / 7.0),
            (18 * 3_600, 60, 1, 6.0 / 7.0),
            (21 * 3_600, 90, 0, 1),
            (24 * 3_600, -90, 0, 0),
        ]

        for item in cases {
            let shadow = SundialTimeMath.shadow(
                secondsAfterMidnight: item.seconds
            )
            XCTAssertEqual(
                shadow.angleDegrees,
                item.angle,
                accuracy: 0.000_1
            )
            XCTAssertEqual(
                shadow.length,
                item.length,
                accuracy: 0.000_1
            )
            XCTAssertEqual(
                shadow.verticalProgress,
                item.verticalProgress,
                accuracy: 0.000_1
            )
        }
    }

    func testShadowInterpolatesContinuouslyBetweenHours() {
        let fourThirty = SundialTimeMath.shadow(
            secondsAfterMidnight: 4.5 * 3_600
        )
        XCTAssertEqual(
            fourThirty.angleDegrees,
            -75,
            accuracy: 0.000_1
        )
        XCTAssertEqual(fourThirty.length, 1, accuracy: 0.000_1)

        let oneThirty = SundialTimeMath.shadow(
            secondsAfterMidnight: 1.5 * 3_600
        )
        XCTAssertEqual(
            oneThirty.angleDegrees,
            -90,
            accuracy: 0.000_1
        )
        XCTAssertEqual(oneThirty.length, 0.5, accuracy: 0.000_1)

        let twentyTwoThirty = SundialTimeMath.shadow(
            secondsAfterMidnight: 22.5 * 3_600
        )
        XCTAssertEqual(
            twentyTwoThirty.angleDegrees,
            90,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            twentyTwoThirty.length,
            0,
            accuracy: 0.000_1
        )
    }

    func testGnomonProjectionChangesTheShadowSilhouette() {
        let lauds = SundialTimeMath.shadow(
            secondsAfterMidnight: 3 * 3_600
        )
        let prime = SundialTimeMath.shadow(
            secondsAfterMidnight: 6 * 3_600
        )
        let terce = SundialTimeMath.shadow(
            secondsAfterMidnight: 9 * 3_600
        )
        let sext = SundialTimeMath.shadow(
            secondsAfterMidnight: 12 * 3_600
        )
        let none = SundialTimeMath.shadow(
            secondsAfterMidnight: 15 * 3_600
        )
        let vespers = SundialTimeMath.shadow(
            secondsAfterMidnight: 18 * 3_600
        )
        let compline = SundialTimeMath.shadow(
            secondsAfterMidnight: 21 * 3_600
        )

        XCTAssertLessThan(
            lauds.centerlineDepth,
            prime.centerlineDepth
        )
        XCTAssertLessThan(
            prime.centerlineDepth,
            sext.centerlineDepth
        )
        XCTAssertEqual(
            prime.centerlineDepth,
            vespers.centerlineDepth,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            terce.centerlineDepth,
            none.centerlineDepth,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            compline.centerlineDepth,
            0,
            accuracy: 0.000_1
        )

        XCTAssertGreaterThan(
            apparentAreaFactor(for: prime),
            apparentAreaFactor(for: lauds)
        )
        XCTAssertEqual(
            apparentAreaFactor(for: sext),
            0,
            accuracy: 0.000_1
        )
    }

    func testShadowUsesANarrowOffscreenBaseBetweenTertiaAndSexta() {
        let matins = SundialTimeMath.shadow(
            secondsAfterMidnight: 0
        )
        let halfway = SundialTimeMath.shadow(
            secondsAfterMidnight: 1.5 * 3_600
        )
        let lauds = SundialTimeMath.shadow(
            secondsAfterMidnight: 3 * 3_600
        )

        XCTAssertEqual(halfway.length, 0.5, accuracy: 0.000_1)
        XCTAssertEqual(
            halfway.centerlineDepth,
            lauds.centerlineDepth / 2,
            accuracy: 0.000_1
        )

        let layout = SundialLayout(
            size: CGSize(width: 393, height: 500)
        )
        let matinsSource = layout.shadowSource(for: matins)
        let halfwaySource = layout.shadowSource(for: halfway)
        let laudsSource = layout.shadowSource(for: lauds)
        let matinsTip = layout.shadowTip(for: matins)
        let halfwayTip = layout.shadowTip(for: halfway)
        let laudsTip = layout.shadowTip(for: lauds)
        let matinsBounds = layout.shadowPath(
            for: matins
        ).boundingRect
        let laudsBounds = layout.shadowPath(
            for: lauds
        ).boundingRect

        XCTAssertEqual(matinsSource.x, halfwaySource.x)
        XCTAssertEqual(matinsSource.y, halfwaySource.y)
        XCTAssertEqual(matinsSource.x, laudsSource.x)
        XCTAssertEqual(matinsSource.y, laudsSource.y)
        XCTAssertLessThan(matinsSource.x, 0)
        XCTAssertEqual(
            matinsSource.y,
            (
                layout.labelPosition(for: .terce).y
                    + layout.labelPosition(for: .sext).y
            ) / 2,
            accuracy: 0.000_1
        )

        XCTAssertLessThan(matinsTip.y, 0)
        XCTAssertGreaterThan(halfwayTip.x, matinsTip.x)
        XCTAssertGreaterThan(halfwayTip.y, matinsTip.y)
        XCTAssertGreaterThan(laudsTip.x, halfwayTip.x)
        XCTAssertGreaterThan(laudsTip.y, halfwayTip.y)
        XCTAssertGreaterThan(matinsBounds.height, 220)
        XCTAssertLessThan(matinsBounds.width, 40)
        XCTAssertLessThan(
            laudsBounds.height,
            175,
            "The offscreen base should remain narrow."
        )
        XCTAssertGreaterThan(
            laudsBounds.width,
            matinsBounds.width * 5
        )
    }

    func testShadowTipExtendsInsideTheHourLabelColumn() {
        let layout = SundialLayout(
            size: CGSize(width: 393, height: 500)
        )
        let lauds = SundialTimeMath.shadow(for: .lauds)
        let tip = layout.shadowTip(for: lauds)
        let rowCenter = layout.labelPosition(for: .lauds)
        let labelCenter =
            rowCenter.x
                - (
                    SundialLayout.disclosureWidth
                        + SundialLayout.disclosureSpacing
                ) / 2

        XCTAssertGreaterThan(
            tip.x,
            labelCenter - 20
        )
        XCTAssertLessThan(tip.x, labelCenter)
    }

    func testAmbientSkyMovesFromNightThroughDayAndDusk() {
        let matins = SundialTimeMath.ambientSky(
            secondsAfterMidnight: 0
        )
        let lauds = SundialTimeMath.ambientSky(
            secondsAfterMidnight: 3 * 3_600
        )
        let sext = SundialTimeMath.ambientSky(
            secondsAfterMidnight: 12 * 3_600
        )
        let none = SundialTimeMath.ambientSky(
            secondsAfterMidnight: 15 * 3_600
        )
        let vespers = SundialTimeMath.ambientSky(
            secondsAfterMidnight: 18 * 3_600
        )

        XCTAssertGreaterThan(matins.darkness, lauds.darkness)
        XCTAssertGreaterThan(lauds.darkness, sext.darkness)
        XCTAssertGreaterThan(
            lauds.lowerRed,
            lauds.lowerBlue
        )
        XCTAssertGreaterThan(
            sext.upperBlue,
            sext.upperRed
        )
        XCTAssertGreaterThan(
            vespers.lowerRed,
            vespers.lowerBlue
        )
        XCTAssertGreaterThan(vespers.backgroundRed, 0.8)
        XCTAssertGreaterThan(vespers.backgroundGreen, 0.75)
        XCTAssertGreaterThan(vespers.backgroundBlue, 0.75)
        XCTAssertLessThan(
            vespers.backgroundRed,
            none.backgroundRed
        )
        XCTAssertLessThan(
            vespers.backgroundGreen,
            none.backgroundGreen
        )
        XCTAssertLessThan(
            vespers.backgroundBlue,
            none.backgroundBlue
        )
    }

    func testDarkHoursShareOneShadowlessAppearance() {
        let matins = SundialTimeMath.ambientSky(for: .matins)
        let compline = SundialTimeMath.ambientSky(for: .compline)

        XCTAssertEqual(matins, compline)
        XCTAssertEqual(matins.shadowStrength, 0)
        XCTAssertEqual(
            SundialTimeMath.shadow(for: .matins).length,
            0
        )
        XCTAssertEqual(
            SundialTimeMath.shadow(for: .compline).length,
            0
        )
        XCTAssertTrue(
            SundialTimeMath.prefersDarkAppearance(for: .matins)
        )
        XCTAssertTrue(
            SundialTimeMath.prefersDarkAppearance(for: .compline)
        )
        XCTAssertFalse(
            SundialTimeMath.prefersDarkAppearance(for: .lauds)
        )
    }

    func testEveryHourUsesItsCanonicalAmbientSky() {
        for hour in OfficeHour.allCases {
            XCTAssertEqual(
                SundialTimeMath.displayedAmbientSky(for: hour),
                SundialTimeMath.ambientSky(for: hour),
                "\(hour) should keep its canonical color until the next hour."
            )
        }
    }

    func testLaudsAndVespersKeepSubtleDawnAndDuskTints() {
        let lauds = SundialTimeMath.ambientSky(for: .lauds)
        let vespers = SundialTimeMath.ambientSky(for: .vespers)

        for sky in [lauds, vespers] {
            XCTAssertGreaterThan(sky.backgroundRed, 0.9)
            XCTAssertGreaterThan(sky.backgroundGreen, 0.9)
            XCTAssertGreaterThanOrEqual(sky.backgroundBlue, 0.9)
            XCTAssertLessThan(sky.darkness, 0.3)
            XCTAssertLessThan(sky.accentStrength, 0.75)
            XCTAssertLessThan(sky.shadowStrength, 0.35)
        }

        XCTAssertGreaterThan(lauds.lowerRed, lauds.lowerBlue)
        XCTAssertGreaterThan(vespers.lowerRed, vespers.lowerBlue)
    }

    func testAmbientSkyInterpolatesSmoothlyBetweenHours() {
        let lauds = SundialTimeMath.ambientSky(
            secondsAfterMidnight: 3 * 3_600
        )
        let halfwayToPrime = SundialTimeMath.ambientSky(
            secondsAfterMidnight: 4.5 * 3_600
        )
        let prime = SundialTimeMath.ambientSky(
            secondsAfterMidnight: 6 * 3_600
        )

        XCTAssertEqual(
            halfwayToPrime.darkness,
            (lauds.darkness + prime.darkness) / 2,
            accuracy: 0.000_1
        )
        XCTAssertGreaterThan(
            halfwayToPrime.upperBlue,
            lauds.upperBlue
        )
        XCTAssertLessThan(
            halfwayToPrime.upperBlue,
            prime.upperBlue
        )
    }

    func testShadowUsesTheCalendarsLocalWallClock() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(
            TimeZone(secondsFromGMT: 0)
        )
        let noonUTC = try XCTUnwrap(
            utc.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 23,
                    hour: 12
                )
            )
        )

        var centralDaylight = Calendar(identifier: .gregorian)
        centralDaylight.timeZone = try XCTUnwrap(
            TimeZone(secondsFromGMT: -5 * 3_600)
        )

        XCTAssertEqual(
            SundialTimeMath.shadow(
                at: noonUTC,
                calendar: utc
            ).angleDegrees,
            0,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            SundialTimeMath.shadow(
                at: noonUTC,
                calendar: centralDaylight
            ).angleDegrees,
            -50,
            accuracy: 0.000_1
        )
    }

    func testInitialShadowAnimationUsesOneLocalTimeTarget() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(
            TimeZone(secondsFromGMT: 0)
        )

        func date(hour: Int, minute: Int = 0) throws -> Date {
            try XCTUnwrap(
                calendar.date(
                    from: DateComponents(
                        year: 2026,
                        month: 7,
                        day: 23,
                        hour: hour,
                        minute: minute
                    )
                )
            )
        }

        let matins = SundialInitialAnimationPlan.presentation(
            at: try date(hour: 1, minute: 30),
            calendar: calendar
        )
        XCTAssertNil(matins)

        let laudsDate = try date(hour: 4, minute: 30)
        let lauds = SundialInitialAnimationPlan.presentation(
            at: laudsDate,
            calendar: calendar
        )
        XCTAssertEqual(
            lauds,
            SundialPresentation.live(for: .lauds)
        )

        let sextDate = try date(hour: 12)
        let sext = SundialInitialAnimationPlan.presentation(
            at: sextDate,
            calendar: calendar
        )
        XCTAssertEqual(
            sext,
            SundialPresentation.live(for: .sext)
        )

        let lateVespers = SundialInitialAnimationPlan.presentation(
            at: try date(hour: 19, minute: 49),
            calendar: calendar
        )
        XCTAssertEqual(
            lateVespers,
            SundialPresentation.live(for: .vespers)
        )
        XCTAssertEqual(
            lateVespers?.shadow,
            SundialTimeMath.shadow(for: .vespers)
        )
        XCTAssertGreaterThan(
            lateVespers?.shadow.length ?? 0,
            0.9,
            "Opening late in Vespers should still show the Vespers shadow."
        )
    }

    func testInitialShadowProjectionPassesContinuouslyThroughLauds() {
        let target = SundialTimeMath.shadow(for: .none)
        let start = SundialLaunchProjection.shadow(
            toward: target,
            progress: 0
        )
        let lauds = SundialLaunchProjection.shadow(
            toward: target,
            progress: SundialLaunchProjection.entranceFraction
        )
        let end = SundialLaunchProjection.shadow(
            toward: target,
            progress: 1
        )

        XCTAssertEqual(start, SundialTimeMath.shadow(for: .matins))
        XCTAssertEqual(lauds, SundialTimeMath.shadow(for: .lauds))
        XCTAssertEqual(end, target)
    }

    func testLiveMatinsKeepsTheShadowHidden() {
        XCTAssertEqual(
            SundialPresentation.live(for: .matins),
            .matins
        )
    }

    func testDaylightSavingJumpFollowsDisplayedLocalTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(
            TimeZone(identifier: "America/Chicago")
        )
        let beforeJump = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 3,
                    day: 8,
                    hour: 1,
                    minute: 59
                )
            )
        )
        let afterJump = beforeJump.addingTimeInterval(2 * 60)

        let before = SundialTimeMath.shadow(
            at: beforeJump,
            calendar: calendar
        )
        let after = SundialTimeMath.shadow(
            at: afterJump,
            calendar: calendar
        )

        XCTAssertEqual(before.angleDegrees, -90, accuracy: 0.000_1)
        XCTAssertLessThan(before.length, 1)
        XCTAssertEqual(after.length, 1, accuracy: 0.000_1)
        XCTAssertGreaterThan(after.angleDegrees, -90)
    }

    private func apparentAreaFactor(
        for shadow: SundialTimeMath.Shadow
    ) -> Double {
        abs(sin(shadow.angleDegrees * .pi / 180))
            * shadow.centerlineDepth
            * shadow.length
    }
}
