import HoursCore
import UIKit
import XCTest
@testable import Hours

@MainActor
final class ProceduralHourWheelTests: XCTestCase {
    func testWheelRotationParticipatesInSwiftUIAnimation() {
        var wheel = ProceduralHourWheelView(rotationDegrees: 12)

        XCTAssertEqual(wheel.animatableData, 12)
        XCTAssertEqual(wheel.selectedHour, .compline)
        wheel.animatableData = 34
        XCTAssertEqual(wheel.rotationDegrees, 34)
    }

    func testForegroundMatchesPrimaryTextContrastForEachAppearance() {
        let light = HourWheelPalette.colors(for: .light)
        let dark = HourWheelPalette.colors(for: .dark)

        XCTAssertEqual(light.foreground, SIMD3<Float>(repeating: 0.06))
        XCTAssertEqual(dark.foreground, SIMD3<Float>(repeating: 0.92))
        XCTAssertEqual(light.mutedBorder, SIMD3<Float>(repeating: 0.42))
        XCTAssertEqual(dark.mutedBorder, SIMD3<Float>(repeating: 0.58))
        XCTAssertEqual(
            light.timeRingFill,
            SIMD3<Float>(repeating: 0.06)
        )
        XCTAssertEqual(
            dark.timeRingFill,
            SIMD3<Float>(repeating: 0.04)
        )
        XCTAssertEqual(
            light.timeRingNumeral,
            SIMD3<Float>(repeating: 0.92)
        )
        XCTAssertEqual(
            dark.timeRingNumeral,
            SIMD3<Float>(repeating: 0.92)
        )
        XCTAssertEqual(light.jerusalemCrossFill, light.timeRingFill)
        XCTAssertEqual(dark.jerusalemCrossFill, dark.timeRingFill)
        XCTAssertEqual(
            light.jerusalemCrossForeground,
            light.timeRingNumeral
        )
        XCTAssertEqual(
            dark.jerusalemCrossForeground,
            dark.timeRingNumeral
        )
        XCTAssertEqual(
            light.selectedLabel,
            SIMD3<Float>(0.68, 0.12, 0.09)
        )
        XCTAssertEqual(dark.selectedLabel, light.selectedLabel)
        XCTAssertEqual(
            HourWheelPalette.interpolatedTimeRingFill(at: 0),
            light.timeRingFill
        )
        let midpointFill =
            HourWheelPalette.interpolatedTimeRingFill(at: 0.5)
        XCTAssertEqual(midpointFill.x, 0.05, accuracy: 0.000_1)
        XCTAssertEqual(midpointFill.y, 0.05, accuracy: 0.000_1)
        XCTAssertEqual(midpointFill.z, 0.05, accuracy: 0.000_1)
        XCTAssertEqual(
            HourWheelPalette.interpolatedTimeRingFill(at: 1),
            dark.timeRingFill
        )
        let midpoint = HourWheelPalette.interpolated(at: 0.5)
        XCTAssertEqual(midpoint.foreground.x, 0.49, accuracy: 0.000_1)
        XCTAssertEqual(midpoint.mutedBorder.x, 0.5, accuracy: 0.000_1)
        XCTAssertEqual(midpoint.timeRingFill.x, 0.05, accuracy: 0.000_1)
        XCTAssertEqual(
            midpoint.timeRingNumeral,
            light.timeRingNumeral
        )
        XCTAssertEqual(midpoint.selectedLabel, light.selectedLabel)
        XCTAssertEqual(HourWheelAppearanceTransition.duration, 0.72)
    }

    func testWorldRotationMatchesSwiftUIClockwiseRotation() {
        XCTAssertEqual(
            HourWheelGeometry.worldRotationRadians(
                forDisplayedDegrees: 90
            ),
            -.pi / 2,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            HourWheelGeometry.worldRotationRadians(
                forDisplayedDegrees: -270
            ),
            3 * .pi / 2,
            accuracy: 0.000_1
        )
    }

    func testWorldSectorRangesCoverTheFullWheel() {
        let ranges = OfficeHour.allCases.map {
            HourWheelGeometry.worldSectorAngles(for: $0)
        }

        XCTAssertTrue(
            ranges.allSatisfy { $0.lowerBound < $0.upperBound }
        )

        let totalSpan = ranges.reduce(Float.zero) {
            $0 + $1.upperBound - $1.lowerBound
        }
        XCTAssertEqual(totalSpan, 2 * .pi, accuracy: 0.000_1)
    }

    func testLabelPositionsFollowTheAutomaticHourSchedule() {
        let radius: Float = 0.4
        let expectedAngles = [
            30, 75, 105, 135,
            172.5, 217.5, 270, 330
        ]

        for (index, hour) in OfficeHour.allCases.enumerated() {
            let expectedAngle = expectedAngles[index] * .pi / 180
            let position = HourWheelGeometry.position(
                for: hour,
                radius: radius
            )
            XCTAssertEqual(
                position.x,
                radius * Float(sin(expectedAngle)),
                accuracy: 0.000_1
            )
            XCTAssertEqual(
                position.y,
                radius * Float(cos(expectedAngle)),
                accuracy: 0.000_1
            )
        }
    }

    func testOfficeNamesSitOutsideTheRomanNumeralRing() {
        XCTAssertGreaterThan(
            HourWheelGeometry.labelRadius,
            HourWheelGeometry.wheelRadius
        )
        XCTAssertGreaterThan(
            HourWheelGeometry.numeralRadius,
            HourWheelGeometry.timeRingInnerRadius
        )
        XCTAssertLessThan(
            HourWheelGeometry.numeralRadius,
            HourWheelGeometry.wheelRadius
        )
    }

    func testTexturesAreUprightAtTheirSelectionDetents() {
        XCTAssertEqual(
            HourWheelGeometry.texturedSectorOuterRadius,
            HourWheelGeometry.timeRingInnerRadius,
            accuracy: 0.000_1
        )

        for hour in [
            OfficeHour.matins, .lauds, .prime, .terce, .sext, .none,
            .vespers, .compline,
        ] {
            let centerAngle = HourWheelGeometry.worldAngle(
                forDialDegrees: HourDialMath.labelAngle(for: hour)
            )
            let selectedCenterAngle = centerAngle
                + HourWheelGeometry.selectedRotationRadians(for: hour)
            let normalizedCenterAngle = atan2(
                sin(selectedCenterAngle),
                cos(selectedCenterAngle)
            )

            XCTAssertEqual(
                normalizedCenterAngle,
                .pi / 2,
                accuracy: 0.000_1
            )

            let centerPoint = HourWheelGeometry.position(
                for: hour,
                radius: HourWheelGeometry.texturedSectorOuterRadius
            )
            let textureCoordinate =
                HourWheelGeometry.textureCoordinate(
                    forWheelPoint: centerPoint,
                    in: hour
                )
            XCTAssertEqual(
                textureCoordinate.x,
                0.5,
                accuracy: 0.000_1
            )
            XCTAssertGreaterThan(textureCoordinate.y, 0.5)
        }
    }

    func testTextureDividersFollowEverySectorBoundary() {
        XCTAssertEqual(
            HourWheelGeometry.textureDividerAngles.count,
            OfficeHour.allCases.count
        )
        XCTAssertGreaterThan(HourWheelGeometry.textureDividerWidth, 0)
        XCTAssertLessThan(
            HourWheelGeometry.textureDividerWidth,
            HourWheelGeometry.timeRingInnerRadius
                - HourWheelGeometry.centerBorderRadius
        )

        for (hour, dividerAngle) in zip(
            OfficeHour.allCases,
            HourWheelGeometry.textureDividerAngles
        ) {
            XCTAssertEqual(
                dividerAngle,
                HourWheelGeometry.worldSectorAngles(for: hour).lowerBound,
                accuracy: 0.000_1
            )
        }
    }

    func testAncientTimeScaleContainsTwelveDayAndNightHours() {
        let daylightMarkers =
            HourWheelGeometry.ancientTimeMarkers.filter {
                $0.period == .daylight
            }
        let nightMarkers =
            HourWheelGeometry.ancientTimeMarkers.filter {
                $0.period == .night
            }
        let expectedNumerals = [
            "I", "II", "III", "IV", "V", "VI",
            "VII", "VIII", "IX", "X", "XI", "XII"
        ]

        XCTAssertEqual(daylightMarkers.map(\.numeral), expectedNumerals)
        XCTAssertEqual(
            nightMarkers.map(\.numeral).sorted {
                expectedNumerals.firstIndex(of: $0)!
                    < expectedNumerals.firstIndex(of: $1)!
            },
            expectedNumerals
        )
        XCTAssertEqual(HourWheelGeometry.ancientTimeMarkers.count, 24)
    }

    func testAncientTimeMarkersAreEvenlySpaced() {
        let angles = HourWheelGeometry.ancientTimeMarkers.map(\.dialAngle)

        for index in angles.indices {
            let nextAngle = index == angles.indices.last
                ? angles[0] + 360
                : angles[index + 1]
            XCTAssertEqual(
                nextAngle - angles[index],
                15,
                accuracy: 0.000_1
            )
        }
    }

    func testDaylightOfficeNamesAlignWithAncientHours() {
        let expectedMarkers: [(Double, String)] = [
            (97.5, "I"),
            (127.5, "III"),
            (172.5, "VI"),
            (217.5, "IX"),
            (262.5, "XII")
        ]

        for (angle, numeral) in expectedMarkers {
            let marker = HourWheelGeometry.ancientTimeMarkers.first {
                $0.period == .daylight && $0.dialAngle == angle
            }
            XCTAssertEqual(marker?.numeral, numeral)
        }
    }

    func testNightOfficeNamesAlignWithAncientHours() {
        let expectedMarkers: [(Double, String)] = [
            (292.5, "II"),
            (352.5, "VI"),
            (52.5, "X")
        ]

        for (angle, numeral) in expectedMarkers {
            let marker = HourWheelGeometry.ancientTimeMarkers.first {
                $0.period == .night && $0.dialAngle == angle
            }
            XCTAssertEqual(marker?.numeral, numeral)
        }
    }

    func testLaudsOccupiesTheFinalTwoNightHours() {
        let laudsRange = HourDialMath.sectorAngleRange(for: .lauds)
        let laudsNightNumerals = HourWheelGeometry.ancientTimeMarkers
            .filter {
                $0.period == .night
                    && laudsRange.contains($0.dialAngle)
            }
            .map(\.numeral)

        XCTAssertEqual(laudsNightNumerals, ["XI", "XII"])
    }

    func testEveryOfficeUsesATexturedSector() {
        XCTAssertEqual(
            HourDialMath.sectors.map(\.hour),
            OfficeHour.allCases
        )
        XCTAssertEqual(
            Set(HourDialMath.sectors.map(\.textureAssetName)).count,
            OfficeHour.allCases.count
        )
        XCTAssertLessThan(
            HourWheelGeometry.centerOpeningRadius,
            HourWheelGeometry.centerBorderRadius
        )
        XCTAssertEqual(
            HourWheelGeometry.centerOutlineWidth,
            HourWheelGeometry.centerBorderRadius * 0.020,
            accuracy: 0.000_4
        )
    }

    func testCanvasArtworkLoadsEverySectorTexture() {
        XCTAssertEqual(
            HourWheelCanvasArtwork.textureAssetNamesByHour.count,
            OfficeHour.allCases.count
        )

        for hour in OfficeHour.allCases {
            let assetName =
                HourWheelCanvasArtwork.textureAssetNamesByHour[hour]
            XCTAssertNotNil(assetName)
            XCTAssertNotNil(
                assetName.flatMap {
                    UIImage(
                        named: $0,
                        in: .main,
                        compatibleWith: nil
                    )
                }
            )
        }
    }

    func testCanvasArtworkBuildsEveryCurvedLabelAndNumeral() {
        XCTAssertEqual(
            HourWheelCanvasArtwork.labelPaths.count,
            OfficeHour.allCases.count
        )
        XCTAssertTrue(
            HourWheelCanvasArtwork.labelPaths.values.allSatisfy {
                !$0.cgPath.isEmpty
            }
        )
        XCTAssertFalse(HourWheelCanvasArtwork.numeralPath.cgPath.isEmpty)
    }

    func testCanvasSectorPathsHaveAreaAndStayInsideWheel() {
        for hour in OfficeHour.allCases {
            let bounds =
                HourWheelCanvasArtwork.sectorPath(for: hour).boundingRect
            XCTAssertGreaterThan(bounds.width, 0)
            XCTAssertGreaterThan(bounds.height, 0)
            XCTAssertLessThanOrEqual(
                bounds.maxX,
                CGFloat(HourWheelGeometry.texturedSectorOuterRadius)
                    + 0.000_1
            )
            XCTAssertGreaterThanOrEqual(
                bounds.minX,
                -CGFloat(HourWheelGeometry.texturedSectorOuterRadius)
                    - 0.000_1
            )
        }
    }

    func testDrawingExtentFitsEntireWheelInsideItsBounds() {
        XCTAssertGreaterThan(
            HourWheelGeometry.canvasArtworkExtent,
            CGFloat(HourWheelGeometry.labelRadius)
        )
    }

    func testArtworkOnlyRendersForFiniteNonzeroLayout() {
        XCTAssertFalse(
            HourWheelGeometry.canRender(size: .zero)
        )
        XCTAssertFalse(
            HourWheelGeometry.canRender(
                size: CGSize(width: 390, height: 0)
            )
        )
        XCTAssertFalse(
            HourWheelGeometry.canRender(
                size: CGSize(width: CGFloat.infinity, height: 390)
            )
        )
        XCTAssertTrue(
            HourWheelGeometry.canRender(
                size: CGSize(width: 390, height: 390)
            )
        )
    }
}
