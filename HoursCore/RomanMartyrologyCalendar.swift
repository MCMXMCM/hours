import Foundation

public enum RomanMartyrologyCalendar {
    public static let latinProclamationToken =
        "{{hours:prime-martyrology-latin-proclamation}}"
    public static let englishProclamationToken =
        "{{hours:prime-martyrology-english-proclamation}}"
    /// The Moon and the year in words, as the approved exceptional readings
    /// give them: "The sixteenth day of the Moon. In the year of our Lord 2026."
    public static let englishFormalProclamationToken =
        "{{hours:prime-martyrology-english-formal-proclamation}}"

    private static let latinLunarOrdinals = [
        "prima", "secúnda", "tértia", "quarta", "quinta", "sexta",
        "séptima", "octáva", "nona", "décima", "undécima", "duodécima",
        "tértia décima", "quarta décima", "quinta décima", "sexta décima",
        "décima séptima", "duodevicésima", "undevicésima", "vicésima",
        "vicésima prima", "vicésima secúnda", "vicésima tértia",
        "vicésima quarta", "vicésima quinta", "vicésima sexta",
        "vicésima séptima", "vicésima octáva", "vicésima nona", "tricésima"
    ]

    private static let englishLunarOrdinals = [
        "first", "second", "third", "fourth", "fifth", "sixth", "seventh",
        "eighth", "ninth", "tenth", "eleventh", "twelfth", "thirteenth",
        "fourteenth", "fifteenth", "sixteenth", "seventeenth", "eighteenth",
        "nineteenth", "twentieth", "twenty-first", "twenty-second",
        "twenty-third", "twenty-fourth", "twenty-fifth", "twenty-sixth",
        "twenty-seventh", "twenty-eighth", "twenty-ninth", "thirtieth"
    ]

    private static let englishMonths = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    /// The ecclesiastical age of the Moon proclaimed in the Martyrology: from
    /// the epact table of 1900 through 2199 as reviewed, and in other years
    /// from the Gregorian calendar of epacts, whose table changes with the
    /// solar equation of 2200.
    public static func lunarDay(for day: LocalDay) -> Int {
        if (1900..<2200).contains(day.year) {
            return gregorianTableLunarDay(for: day)
        }
        let age = epactCalendarLunarDay(for: day)
        // The calendar of epacts has exceptions this does not model (a
        // golden number of 19 with the epact xix). None falls before 2300;
        // an age it cannot give is taken from the mean Moon instead.
        return (1...30).contains(age) ? age : continuousLunarDay(for: day)
    }

    public static func latinProclamation(for day: LocalDay) -> String {
        let lunarDay = lunarDay(for: day)
        return "Luna \(latinLunarOrdinals[lunarDay - 1]) Anno Dómini \(day.year)"
    }

    public static func englishProclamation(for day: LocalDay) -> String {
        let lunarDay = lunarDay(for: day)
        return "\(englishMonths[day.month - 1]) \(day.day)\(ordinalSuffix(day.day)) "
            + "\(day.year), the \(lunarDay)\(ordinalSuffix(lunarDay)) day of the Moon,"
    }

    public static func englishFormalProclamation(for day: LocalDay) -> String {
        "The \(englishLunarOrdinals[lunarDay(for: day) - 1]) day of the Moon. "
            + "In the year of our Lord \(day.year)."
    }

    private static let proclamationTokens = [
        latinProclamationToken,
        englishProclamationToken,
        englishFormalProclamationToken
    ]

    /// Whether a stored text leaves the Moon and the year to be named.
    public static func awaitsProclamation(_ text: String) -> Bool {
        text.contains("{{hours:prime-martyrology-")
    }

    /// A stored text naming the Moon and the year of `day`, as it is read at
    /// Prime of the day before.
    public static func proclaiming(_ text: String, on day: LocalDay) -> String {
        guard awaitsProclamation(text) else { return text }
        return text
            .replacingOccurrences(of: latinProclamationToken, with: latinProclamation(for: day))
            .replacingOccurrences(of: englishProclamationToken, with: englishProclamation(for: day))
            .replacingOccurrences(
                of: englishFormalProclamationToken,
                with: englishFormalProclamation(for: day)
            )
    }

    /// A stored text where no day is in view, as among the results of a
    /// search: the Moon and the year are left unsaid, and a line that held
    /// nothing else is omitted.
    public static func withoutProclamation(_ text: String) -> String {
        guard awaitsProclamation(text) else { return text }
        var lines: [String] = []
        var omittedLine = false
        for line in text.components(separatedBy: "\n") {
            // The blank line that set an omitted line apart goes with it.
            if omittedLine, line.isEmpty {
                omittedLine = false
                continue
            }
            omittedLine = false
            guard awaitsProclamation(line) else {
                lines.append(line)
                continue
            }
            let rest = proclamationTokens
                .reduce(line) { $0.replacingOccurrences(of: $1, with: "") }
                .trimmingCharacters(in: .whitespaces)
            if rest.contains(where: { $0.isLetter || $0.isNumber }) {
                lines.append(rest)
            } else {
                omittedLine = true
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func materialize(_ office: OfficeDocument) -> OfficeDocument {
        guard office.hour == .prime,
              let followingDay = LiturgicalOrdoParityValidator.followingDay(
                after: office.date
              ) else {
            return office
        }
        let sections = office.sections.map { section in
            OfficeSection(
                id: section.id,
                kind: section.kind,
                title: section.title,
                titleEnglish: section.titleEnglish,
                rubric: section.rubric,
                rubricEnglish: section.rubricEnglish,
                latin: proclaiming(section.latin, on: followingDay),
                english: section.english.map { proclaiming($0, on: followingDay) },
                chant: section.chant
            )
        }
        return OfficeDocument(
            id: office.id,
            date: office.date,
            hour: office.hour,
            titleLatin: office.titleLatin,
            titleEnglish: office.titleEnglish,
            contextLabel: office.contextLabel,
            sourceVersion: office.sourceVersion,
            format: office.format,
            visibleContentDigest: office.visibleContentDigest,
            observance: office.observance,
            sections: sections
        )
    }

    private static func gregorianTableLunarDay(for input: LocalDay) -> Int {
        let epacts = [29, 10, 21, 2, 13, 24, 5, 16, 27, 8, 19, 30, 11, 22, 3, 14, 25, 6, 17]
        let goldenNumber = input.year % 19
        var lunarMonths = [30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 100]
        lunarMonths[12] = goldenNumber == 18 ? 29 : 30
        if isLeapYear(input.year), input.month > 2 {
            lunarMonths[1] = 30
        }
        if goldenNumber == 0 || goldenNumber == 8 || goldenNumber == 11 {
            lunarMonths.insert(30, at: 0)
        }

        // The bissextile day is counted with February 24, so the Moon's age
        // is repeated on the 25th and the later days of February follow it.
        var calculationDay = input.day
        if isLeapYear(input.year), input.month == 2, input.day >= 25 {
            calculationDay = input.day - 1
        }
        let calculationDate = LocalDay(
            year: input.year,
            month: input.month,
            day: calculationDay
        )
        // Zero-based, as the pinned source computes it from Perl localtime
        // between 1970 and 2037. Its one-based fallback outside that interval
        // proclaims every day one day too old, so it is not reproduced.
        let sourceOrdinal = ordinalDay(calculationDate) - 1
        // After the saltus lunae the last lunation of the nineteenth year has
        // 29 days, so January 1 of the following first year is its 29th day,
        // not the 30th which the source's table yields (for example, 2033).
        if goldenNumber == 0, sourceOrdinal == 0 {
            return 29
        }

        var boundary = -epacts[goldenNumber] - 1
        var index = 0
        while boundary < sourceOrdinal {
            boundary += lunarMonths[index]
            index += 1
        }
        boundary -= lunarMonths[index - 1]
        return sourceOrdinal - boundary
    }

    /// The epact of a Gregorian year, the epact * being written 30.
    static func gregorianEpact(year: Int) -> Int {
        let golden = year % 19
        let century = year / 100
        let value = (11 * golden + 8 - century + century / 4 + (8 * century + 13) / 25) % 30
        let epact = (value + 30) % 30
        return epact == 0 ? 30 : epact
    }

    /// Where the calendar of epacts begins each run of its labels (* xxix …
    /// i), as days of a common year counted from 1 January as zero: 1 and 31
    /// January, 1 and 31 March, 29 April, 29 May, 27 June, 27 July, 25
    /// August, 24 September, 23 October, 22 November and 21 December. The
    /// runs are alternately of thirty days and of twenty-nine.
    private static let epactCycleStarts = [0, 30, 59, 89, 118, 148, 177, 207, 236, 266, 295, 325, 354]

    /// The days of a common year on which the calendar sets a year's epact,
    /// and so its new Moons.
    private static func newMoons(inYear year: Int) -> [Int] {
        let epact = gregorianEpact(year: year)
        // With a golden number above eleven the epact 25 is the calendar's
        // "25", which stands a day earlier in the runs of twenty-nine days.
        let isArabic25 = epact == 25 && year % 19 + 1 > 11
        return epactCycleStarts.enumerated().compactMap { cycle, start in
            let offset: Int
            if cycle.isMultiple(of: 2) {
                offset = 30 - epact
            } else if isArabic25 {
                offset = 4
            } else if epact >= 26 {
                offset = 30 - epact
            } else if epact == 25 {
                // xxv and xxiv share a day.
                offset = 5
            } else {
                offset = 29 - epact
            }
            return start + offset <= 364 ? start + offset : nil
        }
    }

    /// Whether a year's epact follows the preceding year's by the ordinary
    /// eleven (or, after the nineteenth year of the cycle, twelve), with no
    /// solar or lunar equation between them.
    private static func epactContinues(into year: Int) -> Bool {
        let step = (year - 1) % 19 == 18 ? 12 : 11
        return (gregorianEpact(year: year - 1) + step - 1) % 30 + 1 == gregorianEpact(year: year)
    }

    static func epactCalendarLunarDay(for input: LocalDay) -> Int {
        // The bissextile day is counted with February 24, so it has no place
        // of its own in the calendar, and later days stand one place earlier.
        var position = ordinalDay(input) - 1
        if isLeapYear(input.year), input.month > 2 || (input.month == 2 && input.day >= 25) {
            position -= 1
        }
        let moons = newMoons(inYear: input.year)
        if let latest = moons.last(where: { $0 <= position }) {
            return position - latest + 1
        }
        guard let first = moons.first, let previous = newMoons(inYear: input.year - 1).last else {
            return 0
        }
        // Before the year's first new Moon the count runs on from the last
        // of the preceding year, which also shortens the last lunation of a
        // nineteenth year. Where an equation has moved the epacts between
        // the two years it is counted back from the new Moon instead.
        return epactContinues(into: input.year)
            ? position + (365 - previous) + 1
            : 30 - (first - position) + 1
    }

    private static func continuousLunarDay(for day: LocalDay) -> Int {
        let calendar = Roman1960CalendarMath.gregorianUTC
        let epoch = LocalDay(year: 2008, month: 1, day: 1).date(in: calendar)!
        let date = day.date(in: calendar)!
        let elapsed = calendar.dateComponents([.day], from: epoch, to: date).day ?? 0
        let position = Double(elapsed + 23)
        let lunarMonth = 29.53059
        let multiple = floor(position / lunarMonth)
        var distance = Int(floor(position - multiple * lunarMonth - 0.25))
        if distance <= 0 { distance += 30 }
        return distance
    }

    private static func ordinalDay(_ day: LocalDay) -> Int {
        let calendar = Roman1960CalendarMath.gregorianUTC
        let date = day.date(in: calendar)!
        return calendar.ordinality(of: .day, in: .year, for: date)!
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        year.isMultiple(of: 4)
            && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
    }

    private static func ordinalSuffix(_ value: Int) -> String {
        if (11...13).contains(value % 100) { return "th" }
        switch value % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}
