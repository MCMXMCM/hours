import XCTest
@testable import HoursCore

final class Roman1960CalendarTests: XCTestCase {
    func testKnownGregorianEasterDates() {
        let expectations: [Int: LocalDay] = [
            1962: LocalDay(year: 1962, month: 4, day: 22),
            2000: LocalDay(year: 2000, month: 4, day: 23),
            2026: LocalDay(year: 2026, month: 4, day: 5),
            2038: LocalDay(year: 2038, month: 4, day: 25),
            2100: LocalDay(year: 2100, month: 3, day: 28)
        ]
        for (year, expected) in expectations {
            XCTAssertEqual(Roman1960CalendarMath.gregorianEaster(year: year), expected)
        }
    }

    func testEveryReleaseYearProducesASundayWithinGregorianBounds() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for year in 1962...2100 {
            let easter = Roman1960CalendarMath.gregorianEaster(year: year)
            XCTAssertTrue(
                easter.month == 3 && (22...31).contains(easter.day)
                    || easter.month == 4 && (1...25).contains(easter.day),
                "Invalid Easter boundary for \(year)"
            )
            XCTAssertEqual(
                calendar.component(.weekday, from: try XCTUnwrap(easter.date(in: calendar))),
                1,
                "Easter is not Sunday in \(year)"
            )
        }
    }

    func testMovableFeastsUseTheir1960Offsets() {
        let dates = Roman1960CalendarMath.movableObservances(year: 2026)
        XCTAssertEqual(dates[.septuagesimaSunday], LocalDay(year: 2026, month: 2, day: 1))
        XCTAssertEqual(dates[.ashWednesday], LocalDay(year: 2026, month: 2, day: 18))
        XCTAssertEqual(dates[.ascension], LocalDay(year: 2026, month: 5, day: 14))
        XCTAssertEqual(dates[.pentecost], LocalDay(year: 2026, month: 5, day: 24))
        XCTAssertEqual(dates[.corpusChristi], LocalDay(year: 2026, month: 6, day: 4))
    }

    func testNativeProviderRequiresCompleteParity() {
        XCTAssertFalse(
            LiturgicalOrdoParityReport(
                expectedOfficeCount: 406_152,
                matchingOfficeCount: 406_151,
                calendarEdgeCasesPassed: true
            ).enablesNativeProvider
        )
        XCTAssertTrue(
            LiturgicalOrdoParityReport(
                expectedOfficeCount: 406_152,
                matchingOfficeCount: 406_152,
                calendarEdgeCasesPassed: true
            ).enablesNativeProvider
        )
    }

    func testMartyrologyLunarProclamationsMatchPinned2026Source() {
        XCTAssertEqual(
            RomanMartyrologyCalendar.latinProclamation(
                for: LocalDay(year: 2026, month: 2, day: 23)
            ),
            "Luna sexta Anno Dómini 2026"
        )
        XCTAssertEqual(
            RomanMartyrologyCalendar.latinProclamation(
                for: LocalDay(year: 2026, month: 12, day: 25)
            ),
            "Luna sexta décima Anno Dómini 2026"
        )
        XCTAssertEqual(
            RomanMartyrologyCalendar.englishProclamation(
                for: LocalDay(year: 2026, month: 2, day: 23)
            ),
            "February 23rd 2026, the 6th day of the Moon,"
        )
    }

    func testMartyrologyLunarDaysFollowTheGregorianEpactTable() {
        // Independently computed from the Gregorian epacts. In a leap year
        // the bissextile day repeats the Moon's age of February 24.
        let expected: [(LocalDay, Int)] = [
            (LocalDay(year: 2028, month: 2, day: 23), 27),
            (LocalDay(year: 2028, month: 2, day: 24), 28),
            (LocalDay(year: 2028, month: 2, day: 25), 28),
            (LocalDay(year: 2028, month: 2, day: 26), 29),
            (LocalDay(year: 2028, month: 2, day: 29), 3),
            (LocalDay(year: 2028, month: 3, day: 1), 4),
            (LocalDay(year: 2032, month: 12, day: 31), 28),
            (LocalDay(year: 2033, month: 1, day: 1), 29),
            (LocalDay(year: 2033, month: 1, day: 2), 1),
            (LocalDay(year: 1965, month: 4, day: 18), 16),
            // Luna XIV on Sunday, April 2, places Easter on April 9, 2045.
            (LocalDay(year: 2045, month: 4, day: 2), 14)
        ]
        for (day, lunarDay) in expected {
            XCTAssertEqual(
                RomanMartyrologyCalendar.lunarDay(for: day),
                lunarDay,
                "\(day)"
            )
        }
    }

    func testPrimeMaterializesFollowingDayWithoutChangingStoredDigest() {
        let office = OfficeDocument(
            id: "2031-12-31-prime",
            date: LocalDay(year: 2031, month: 12, day: 31),
            hour: .prime,
            titleLatin: "Ad Primam",
            contextLabel: "Feria",
            format: .authoritativeOrdered,
            visibleContentDigest: "stored-template-digest",
            sections: [
                OfficeSection(
                    id: "martyrology",
                    kind: .reading,
                    title: "Martyrologium",
                    latin: "Kaléndis Januárii "
                        + RomanMartyrologyCalendar.latinProclamationToken,
                    english: RomanMartyrologyCalendar.englishProclamationToken
                )
            ]
        )

        let result = RomanMartyrologyCalendar.materialize(office)

        XCTAssertEqual(result.visibleContentDigest, office.visibleContentDigest)
        XCTAssertTrue(result.sections[0].latin.contains("Anno Dómini 2032"))
        XCTAssertTrue(result.sections[0].english?.contains("January 1st 2032") == true)
        XCTAssertFalse(result.sections[0].latin.contains("{{hours:"))
    }

    func testObservanceTitlesOmitTheScriptureWeekMarker() {
        XCTAssertEqual(
            ObservanceTitle.latin("Dominica XIX Post Pentecosten I."),
            "Dominica XIX Post Pentecosten"
        )
        XCTAssertEqual(
            ObservanceTitle.latin("Dominica XVIII Post Pentecosten V. Septembris"),
            "Dominica XVIII Post Pentecosten"
        )
        XCTAssertEqual(
            ObservanceTitle.latin("Dominica V Post Epiphaniam III. Novembris"),
            "Dominica V Post Epiphaniam"
        )
        XCTAssertEqual(
            ObservanceTitle.latin("Feria IV infra Hebdomadam II post Octavam Pentecostes"),
            "Feria IV infra Hebdomadam II post Octavam Pentecostes"
        )
        XCTAssertEqual(
            ObservanceTitle.latin("In Nativitate S. Joannis Baptistæ"),
            "In Nativitate S. Joannis Baptistæ"
        )
        XCTAssertEqual(
            ObservanceTitle.english("the First Sunday of Advent"),
            "The First Sunday of Advent"
        )
        XCTAssertEqual(
            ObservanceTitle.english("the Ninth Sunday after Pentecost, the second"),
            "The Ninth Sunday after Pentecost"
        )
    }
}
