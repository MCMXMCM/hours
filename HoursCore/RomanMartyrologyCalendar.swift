import Foundation

public enum RomanMartyrologyCalendar {
    public static let latinProclamationToken =
        "{{hours:prime-martyrology-latin-proclamation}}"
    public static let englishProclamationToken =
        "{{hours:prime-martyrology-english-proclamation}}"

    private static let latinLunarOrdinals = [
        "prima", "secúnda", "tértia", "quarta", "quinta", "sexta",
        "séptima", "octáva", "nona", "décima", "undécima", "duodécima",
        "tértia décima", "quarta décima", "quinta décima", "sexta décima",
        "décima séptima", "duodevicésima", "undevicésima", "vicésima",
        "vicésima prima", "vicésima secúnda", "vicésima tértia",
        "vicésima quarta", "vicésima quinta", "vicésima sexta",
        "vicésima séptima", "vicésima octáva", "vicésima nona", "tricésima"
    ]

    private static let englishMonths = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    /// The ecclesiastical age of the Moon proclaimed in the Martyrology, from
    /// the Gregorian epact table through 2199. The pinned source's continuous
    /// synodic-month calculation is used after that boundary.
    public static func lunarDay(for day: LocalDay) -> Int {
        if (1900..<2200).contains(day.year) {
            return gregorianTableLunarDay(for: day)
        }
        return continuousLunarDay(for: day)
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

    public static func materialize(_ office: OfficeDocument) -> OfficeDocument {
        guard office.hour == .prime,
              let followingDay = LiturgicalOrdoParityValidator.followingDay(
                after: office.date
              ) else {
            return office
        }
        let latin = latinProclamation(for: followingDay)
        let english = englishProclamation(for: followingDay)
        let sections = office.sections.map { section in
            OfficeSection(
                id: section.id,
                kind: section.kind,
                title: section.title,
                titleEnglish: section.titleEnglish,
                rubric: section.rubric,
                rubricEnglish: section.rubricEnglish,
                latin: section.latin.replacingOccurrences(
                    of: latinProclamationToken,
                    with: latin
                ),
                english: section.english?.replacingOccurrences(
                    of: englishProclamationToken,
                    with: english
                ),
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
