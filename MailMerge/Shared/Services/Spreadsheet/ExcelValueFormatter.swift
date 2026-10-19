import Foundation

/// Turns raw worksheet cell values into the text Excel displays for them, applying each
/// cell's number format.
///
/// Supports the parts of Excel's format language that appear in real mail-merge data:
/// General, fixed decimals, thousands separators and scaling, percentages, currency and
/// other literal text, negative and zero sections, scientific notation, dates, times, and
/// elapsed durations. Built-in formats whose appearance Excel ties to the system region
/// (such as the default short date) follow `locale`.
nonisolated final class ExcelValueFormatter {
    let locale: Locale
    let usesDate1904: Bool

    private var cachedDateFormatters: [String: DateFormatter] = [:]

    init(locale: Locale, usesDate1904: Bool) {
        self.locale = locale
        self.usesDate1904 = usesDate1904
    }

    /// The display text for one cell.
    func displayString(for cell: XLSXCell, sharedStrings: [String], styles: XLSXStyles) -> String {
        let formatID = styles.numberFormatID(forStyleIndex: cell.styleIndex)
        let formatCode = styles.customFormats[formatID]

        switch cell.type {
        case "s":
            guard let index = cell.value.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }),
                  sharedStrings.indices.contains(index) else {
                return ""
            }
            return sharedStrings[index].trimmingCharacters(in: .whitespacesAndNewlines)
        case "inlineStr":
            return (cell.inlineText ?? cell.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        case "str", "e":
            return cell.value ?? ""
        case "b":
            guard let raw = cell.value?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else {
                return ""
            }
            return raw == "1" || raw == "true" ? "TRUE" : "FALSE"
        case "d":
            guard let raw = cell.value, let date = Self.parseISO8601(raw) else {
                return cell.value ?? ""
            }
            // A date cell without a date format still reads as a date in Excel.
            let effectiveID = formatID == 0 && formatCode == nil ? 14 : formatID
            return string(forNumber: serial(for: date), formatID: effectiveID, formatCode: formatCode)
        default:
            guard let raw = cell.value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return ""
            }
            guard let number = Double(raw), number.isFinite else {
                return raw
            }
            return string(forNumber: number, formatID: formatID, formatCode: formatCode)
        }
    }

    /// The original cell date, separate from its possibly ambiguous displayed text.
    func dateValue(for cell: XLSXCell, styles: XLSXStyles) -> Date? {
        if cell.type == "d" { return cell.value.flatMap(Self.parseISO8601) }
        guard cell.type == nil || cell.type == "n",
              let raw = cell.value, let number = Double(raw), number.isFinite else { return nil }
        let id = styles.numberFormatID(forStyleIndex: cell.styleIndex)
        let code = styles.customFormats[id] ?? Self.builtinFormatCodes[id] ?? ""
        guard Self.localeDateFormatIDs.contains(id) || id == 22 ||
              (!code.lowercased().contains("general") && Self.isDateOrTime(Self.elements(of: code))) else { return nil }
        return date(fromSerial: number)
    }

    /// The display text for a number in the format with the given ID. `formatCode` is the
    /// workbook's definition of that ID, if it has one.
    func string(forNumber number: Double, formatID: Int, formatCode: String?) -> String {
        if Self.localeDateFormatIDs.contains(formatID) {
            return localeString(forSerial: number, date: .numeric, time: .omitted)
        }
        if formatID == 22 {
            return localeString(forSerial: number, date: .numeric, time: .shortened)
        }
        if Self.localeTimeFormatIDs.contains(formatID) {
            return localeString(forSerial: number, date: .omitted, time: .shortened)
        }
        guard let code = formatCode ?? Self.builtinFormatCodes[formatID] else {
            return generalString(number)
        }
        return string(forNumber: number, formatCode: code)
    }

    // MARK: - Sections

    private func string(forNumber number: Double, formatCode: String) -> String {
        let sections = Self.sections(of: formatCode)
        var value = number
        var section = sections[0]
        var showsMinusSign = number < 0
        let hasConditions = sections.prefix(2).contains { Self.condition(in: $0) != nil }
        if hasConditions {
            guard let selected = sections.prefix(3).first(where: { section in
                Self.condition(in: section).map { $0(number) } ?? true
            }) else { return "" }
            section = selected
        } else if number < 0, sections.count > 1 {
            section = sections[1]
            value = -number
            showsMinusSign = false
        } else if number == 0, sections.count > 2 {
            section = sections[2]
        }

        let elements = Self.elements(of: section)
        // General may be decorated with a color, locale, sign, or literal suffix.
        for index in elements.indices where index + 7 <= elements.count {
            let word = elements[index..<(index + 7)].compactMap { element -> String? in
                if case .code(let c) = element { return String(c) }
                return nil
            }.joined()
            if word.lowercased() == "general" {
                let prefix = Self.literalText(of: elements[..<index])
                let suffix = Self.literalText(of: elements[(index + 7)...])
                return prefix + generalString(value) + suffix
            }
        }
        if section.trimmingCharacters(in: .whitespaces) == "@" { return generalString(value) }

        if Self.isDateOrTime(elements) {
            return dateString(forSerial: number, elements: elements)
        }
        return numberString(abs(value), elements: elements, showsMinusSign: showsMinusSign && value != 0)
    }

    /// Conditions select numeric sections before sign-based section rules apply.
    private static func condition(in section: String) -> ((Double) -> Bool)? {
        guard let match = section.firstMatch(of: /\[(<=|>=|<>|=|<|>)(-?[0-9]+(?:\.[0-9]+)?)\]/),
              let limit = Double(match.2) else { return nil }
        let operation = String(match.1)
        return { value in
            switch operation {
            case "<=": value <= limit
            case ">=": value >= limit
            case "<>": value != limit
            case "=": value == limit
            case "<": value < limit
            default: value > limit
            }
        }
    }

    // MARK: - Numbers

    private func generalString(_ number: Double) -> String {
        number.formatted(
            .number
                .locale(locale)
                .grouping(.never)
                .precision(.significantDigits(1...15))
        )
    }

    private func numberString(_ magnitude: Double, elements: [FormatElement], showsMinusSign: Bool) -> String {
        let placeholders: Set<Character> = ["0", "#", "?"]
        let isCore: (FormatElement) -> Bool = { element in
            if case .code(let character) = element {
                return placeholders.contains(character) || character == "."
            }
            return false
        }
        guard let first = elements.firstIndex(where: isCore),
              let lastPlaceholder = elements.lastIndex(where: isCore) else {
            // A format with no digits (such as "Yes" or ;;;) shows only its text.
            return Self.literalText(of: elements[...])
        }

        let core = elements[first...lastPlaceholder]
        if core.contains(where: { if case .literal = $0 { return true }; return false }),
           !core.contains(where: { element in
               if case .code(let c) = element { return ".,Ee/%".contains(c) }
               return false
           }) {
            // Phone numbers, ZIP+4, and SSNs are digit masks, not decimal formats.
            var digits = Array(magnitude.rounded(.toNearestOrAwayFromZero).formatted(
                .number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(0))
            ))
            var result = ""
            for element in elements.reversed() {
                if case .code(let c) = element, placeholders.contains(c) {
                    if let digit = digits.popLast() { result.insert(digit, at: result.startIndex) }
                    else if c == "0" { result.insert("0", at: result.startIndex) }
                } else {
                    result = Self.literalText(of: [element][...]) + result
                }
            }
            return (showsMinusSign ? "-" : "") + String(digits) + result
        }

        // Trailing commas right after the digits scale the value by 1,000 each.
        var last = lastPlaceholder
        while last + 1 < elements.count, elements[last + 1] == .code(",") {
            last += 1
        }

        var minimumIntegerDigits = 0
        var minimumFractionDigits = 0
        var maximumFractionDigits = 0
        var usesGrouping = false
        var scalingCommas = 0
        var exponentDigits: Int?
        var isFraction = false
        var seenDecimalPoint = false

        var index = first
        while index <= last {
            guard case .code(let character) = elements[index] else {
                index += 1
                continue
            }
            if exponentDigits != nil {
                if character == "0" { exponentDigits? += 1 }
            } else if character == "E" || character == "e",
                      index + 1 <= last,
                      elements[index + 1] == .code("+") || elements[index + 1] == .code("-") {
                exponentDigits = 0
                index += 1
            } else if character == "/" {
                isFraction = true
            } else if character == "." {
                seenDecimalPoint = true
            } else if character == "," {
                let placeholderFollows = index < last && elements[(index + 1)...last].contains { element in
                    if case .code(let next) = element { return placeholders.contains(next) }
                    return false
                }
                if placeholderFollows && !seenDecimalPoint {
                    usesGrouping = true
                } else {
                    scalingCommas += 1
                }
            } else if seenDecimalPoint {
                if character == "0" { minimumFractionDigits += 1 }
                if placeholders.contains(character) { maximumFractionDigits += 1 }
            } else if character == "0" {
                minimumIntegerDigits += 1
            }
            index += 1
        }

        let prefix = Self.literalText(of: elements[..<first])
        let suffix = Self.literalText(of: elements[(last + 1)...])
        let percentCount = elements.filter { $0 == .code("%") }.count

        var value = magnitude
        value *= pow(100, Double(percentCount))
        value /= pow(1000, Double(scalingCommas))
        value = Self.roundedToFifteenSignificantDigits(value)

        let digits: String
        if isFraction {
            digits = fractionString(value, elements: elements)
        } else if let exponentDigits {
            digits = scientificString(value, minimumFractionDigits: minimumFractionDigits, maximumFractionDigits: maximumFractionDigits, exponentDigits: exponentDigits, integerPlaces: max(1, elements[first...last].prefix { $0 != .code(".") && $0 != .code("E") }.filter { if case .code(let c) = $0 { return placeholders.contains(c) }; return false }.count))
        } else if value == 0, minimumIntegerDigits == 0, minimumFractionDigits == 0 {
            digits = ""
        } else {
            digits = value.formatted(
                .number
                    .locale(locale)
                    .grouping(usesGrouping ? .automatic : .never)
                    .precision(.integerAndFractionLength(
                        integerLimits: minimumIntegerDigits...,
                        fractionLimits: minimumFractionDigits...maximumFractionDigits
                    ))
                    .rounded(rule: .toNearestOrAwayFromZero)
            )
        }
        // Padding such as the trailing space in "#,##0 ;(#,##0)" only aligns columns.
        return ((showsMinusSign ? "-" : "") + prefix + digits + suffix).trimmingCharacters(in: .whitespaces)
    }

    private func fractionString(_ value: Double, elements: [FormatElement]) -> String {
        guard let slash = elements.firstIndex(of: .code("/")) else { return generalString(value) }
        let denominatorPlaces = elements[(slash + 1)...].prefix {
            if case .code(let c) = $0 { return "0#?".contains(c) }; return false
        }.count
        let maximum = Int(pow(10, Double(min(denominatorPlaces, 3)))) - 1
        guard maximum > 0 else { return generalString(value) }
        let whole = value.rounded(.down)
        let fraction = value - whole
        var bestNumerator = 0.0
        var bestDenominator = 1
        var bestError = Double.infinity
        for denominator in 1...maximum {
            let numerator = (fraction * Double(denominator)).rounded(.toNearestOrAwayFromZero)
            let error = abs(fraction - numerator / Double(denominator))
            if error < bestError {
                bestNumerator = numerator
                bestDenominator = denominator
                bestError = error
            }
        }
        if bestNumerator == 0 { return whole == 0 ? "" : generalString(whole) }
        if bestNumerator == Double(bestDenominator) { return generalString(whole + 1) }
        return (whole == 0 ? "" : generalString(whole) + " ") + generalString(bestNumerator) + "/" + bestDenominator.formatted(.number.grouping(.never))
    }

    private func scientificString(_ value: Double, minimumFractionDigits: Int, maximumFractionDigits: Int, exponentDigits: Int, integerPlaces: Int) -> String {
        var exponent = value == 0 ? 0 : Int((log10(value) / Double(integerPlaces)).rounded(.down)) * integerPlaces
        var mantissa = value == 0 ? 0 : value / pow(10, Double(exponent))
        let factor = pow(10, Double(maximumFractionDigits))
        if (mantissa * factor).rounded(.toNearestOrAwayFromZero) / factor >= pow(10, Double(integerPlaces)) {
            mantissa /= pow(10, Double(integerPlaces))
            exponent += integerPlaces
        }
        let mantissaText = mantissa.formatted(
            .number
                .locale(locale)
                .grouping(.never)
                .precision(.fractionLength(minimumFractionDigits...maximumFractionDigits))
                .rounded(rule: .toNearestOrAwayFromZero)
        )
        let exponentText = abs(exponent).formatted(
            .number.grouping(.never).precision(.integerLength(max(exponentDigits, 1)...))
        )
        return "\(mantissaText)E\(exponent < 0 ? "-" : "+")\(exponentText)"
    }

    /// Excel keeps 15 significant digits, so 2.675 (stored as 2.67499…) displays as 2.68.
    private static func roundedToFifteenSignificantDigits(_ value: Double) -> Double {
        guard value != 0, value.isFinite else { return value }
        let magnitude = log10(abs(value)).rounded(.down)
        let scale = pow(10, 14 - magnitude)
        guard scale.isFinite, scale > 0 else { return value }
        let rounded = (value * scale).rounded() / scale
        return rounded.isFinite ? rounded : value
    }

    // MARK: - Dates and Times

    private func dateString(forSerial serial: Double, elements: [FormatElement]) -> String {
        let tokens = Self.dateTokens(from: elements)
        if tokens.contains(where: \.isElapsed) {
            return durationString(serial, tokens: tokens)
        }
        let pattern = Self.icuPattern(for: tokens)
        return dateFormatter(pattern: pattern).string(from: date(fromSerial: serial))
    }

    private func durationString(_ serial: Double, tokens: [DateToken]) -> String {
        let totalSeconds = (abs(serial) * 86_400).rounded()
        var text = serial < 0 ? "-" : ""
        for (index, token) in tokens.enumerated() {
            switch token {
            case .elapsed(let unit, let width):
                let divisor: Double = unit == "h" ? 3_600 : unit == "m" ? 60 : 1
                text += Self.padded((totalSeconds / divisor).rounded(.down), width: width)
            case .run(let unit, let width):
                switch unit {
                case "h": text += Self.padded(((totalSeconds / 3_600).rounded(.down)).truncatingRemainder(dividingBy: 24), width: width)
                case "m" where Self.isMinute(at: index, in: tokens):
                    text += Self.padded(((totalSeconds / 60).rounded(.down)).truncatingRemainder(dividingBy: 60), width: width)
                case "s": text += Self.padded(totalSeconds.truncatingRemainder(dividingBy: 60), width: width)
                default: break
                }
            case .literal(let literal):
                text += literal
            case .amPM, .fraction:
                break
            }
        }
        return text
    }

    private func localeString(forSerial serial: Double, date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
        let style = Date.FormatStyle(
            date: date,
            time: time,
            locale: locale,
            calendar: Calendar(identifier: .gregorian),
            timeZone: .gmt
        )
        return self.date(fromSerial: serial).formatted(style)
    }

    private func dateFormatter(pattern: String) -> DateFormatter {
        if let formatter = cachedDateFormatters[pattern] {
            return formatter
        }
        // Excel format codes are converted to ICU patterns at runtime, which the modern
        // Date.FormatStyle API can't express, so this uses a pattern-based DateFormatter.
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .gmt
        formatter.dateFormat = pattern
        cachedDateFormatters[pattern] = formatter
        return formatter
    }

    /// 1899-12-31 00:00 UTC, day 0 of the 1900 date system.
    private static let epoch1900 = Date(timeIntervalSince1970: -2_209_075_200)
    /// 1904-01-01 00:00 UTC, day 0 of the 1904 date system.
    private static let epoch1904 = Date(timeIntervalSince1970: -2_082_844_800)

    func date(fromSerial serial: Double) -> Date {
        let days: Double
        let epoch: Date
        if usesDate1904 {
            days = serial
            epoch = Self.epoch1904
        } else {
            // Excel counts a nonexistent 1900-02-29 as day 60.
            days = serial >= 60 ? serial - 1 : serial
            epoch = Self.epoch1900
        }
        let seconds = (days * 86_400 * 1_000).rounded() / 1_000
        return epoch.addingTimeInterval(seconds)
    }

    func serial(for date: Date) -> Double {
        if usesDate1904 {
            return date.timeIntervalSince(Self.epoch1904) / 86_400
        }
        let days = date.timeIntervalSince(Self.epoch1900) / 86_400
        return days >= 60 ? days + 1 : days
    }

    private static func parseISO8601(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = try? Date(trimmed, strategy: .iso8601) {
            return date
        }
        return try? Date.ISO8601FormatStyle().year().month().day().parse(trimmed)
    }

    // MARK: - Format Code Parsing

    nonisolated enum FormatElement: Equatable {
        /// Text shown as-is.
        case literal(String)
        /// An unescaped character of the format language.
        case code(Character)
        /// `[h]`, `[mm]`, or `[ss]`: an elapsed duration unit and its minimum width.
        case elapsed(Character, Int)
        case amPM
    }

    /// Splits a format code into its positive, negative, zero, and text sections.
    static func sections(of code: String) -> [String] {
        var sections: [String] = []
        var current = ""
        var isInQuote = false
        var isInBracket = false
        var isEscaped = false
        for character in code {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }
            switch character {
            case "\\" where !isInQuote:
                isEscaped = true
                current.append(character)
            case "\"":
                isInQuote.toggle()
                current.append(character)
            case "[" where !isInQuote:
                isInBracket = true
                current.append(character)
            case "]" where !isInQuote:
                isInBracket = false
                current.append(character)
            case ";" where !isInQuote && !isInBracket:
                sections.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        sections.append(current)
        return sections
    }

    static func elements(of section: String) -> [FormatElement] {
        var result: [FormatElement] = []
        let characters = Array(section)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            switch character {
            case "\"":
                var literal = ""
                index += 1
                while index < characters.count, characters[index] != "\"" {
                    literal.append(characters[index])
                    index += 1
                }
                result.append(.literal(literal))
                index += 1
            case "\\":
                if index + 1 < characters.count {
                    result.append(.literal(String(characters[index + 1])))
                }
                index += 2
            case "_", "*":
                // Padding to the width of the next character, or repeating it to fill the
                // cell. Neither has meaning outside a spreadsheet column.
                index += 2
            case "[":
                var content = ""
                index += 1
                while index < characters.count, characters[index] != "]" {
                    content.append(characters[index])
                    index += 1
                }
                result.append(contentsOf: bracketElements(content))
                index += 1
            case "A", "a":
                let rest = String(characters[index...]).lowercased()
                if rest.hasPrefix("am/pm") {
                    result.append(.amPM)
                    index += 5
                } else if rest.hasPrefix("a/p") {
                    result.append(.amPM)
                    index += 3
                } else {
                    result.append(.code(character))
                    index += 1
                }
            default:
                result.append(.code(character))
                index += 1
            }
        }
        return result
    }

    private static func bracketElements(_ content: String) -> [FormatElement] {
        let lowercased = content.lowercased()
        if let unit = lowercased.first, "hms".contains(unit), lowercased.allSatisfy({ $0 == unit }) {
            return [.elapsed(unit, lowercased.count)]
        }
        if content.hasPrefix("$") {
            // [$€-407] is a currency symbol with a locale; [$-409] is only a locale.
            let symbol = content.dropFirst().prefix { $0 != "-" }
            return symbol.isEmpty ? [] : [.literal(String(symbol))]
        }
        // Colors do not change text; conditions are evaluated when selecting a section.
        return []
    }

    private static func isDateOrTime(_ elements: [FormatElement]) -> Bool {
        var hasMonthOrMinute = false
        var hasDigitPlaceholder = false
        for (index, element) in elements.enumerated() {
            switch element {
            case .elapsed, .amPM:
                return true
            case .code(let character):
                switch Character(character.lowercased()) {
                case "y", "d", "h", "s": return true
                case "e":
                    // "E+" and "E-" are scientific notation; a bare "e" is a year.
                    let next = elements[safe: index + 1]
                    if next != .code("+") && next != .code("-") { return true }
                case "m": hasMonthOrMinute = true
                case "0", "#", "?": hasDigitPlaceholder = true
                default: break
                }
            case .literal:
                break
            }
        }
        return hasMonthOrMinute && !hasDigitPlaceholder
    }

    private static func literalText(of elements: ArraySlice<FormatElement>) -> String {
        elements.reduce(into: "") { text, element in
            switch element {
            case .literal(let literal): text += literal
            case .code(let character): text.append(character)
            case .elapsed, .amPM: break
            }
        }
    }

    // MARK: - Date Tokens

    nonisolated enum DateToken: Equatable {
        /// A run of the same date or time letter, such as `yyyy` or `mm`.
        case run(Character, Int)
        case literal(String)
        case amPM
        /// Fractional seconds with the given number of digits.
        case fraction(Int)
        case elapsed(Character, Int)

        var isElapsed: Bool {
            if case .elapsed = self { return true }
            return false
        }
    }

    static func dateTokens(from elements: [FormatElement]) -> [DateToken] {
        var tokens: [DateToken] = []
        var index = 0
        while index < elements.count {
            switch elements[index] {
            case .code(let character):
                let unit = Character(character.lowercased())
                if "ymdhse".contains(unit) {
                    var count = 1
                    while index + count < elements.count,
                          case .code(let next) = elements[index + count],
                          Character(next.lowercased()) == unit {
                        count += 1
                    }
                    // "e" is the year in some locales' formats.
                    tokens.append(unit == "e" ? .run("y", 4) : .run(unit, count))
                    index += count
                    continue
                }
                if character == "." {
                    var zeros = 0
                    while index + 1 + zeros < elements.count, elements[index + 1 + zeros] == .code("0") {
                        zeros += 1
                    }
                    if zeros > 0 {
                        tokens.append(.fraction(zeros))
                        index += 1 + zeros
                        continue
                    }
                }
                tokens.append(.literal(String(character)))
            case .literal(let literal):
                tokens.append(.literal(literal))
            case .amPM:
                tokens.append(.amPM)
            case .elapsed(let unit, let width):
                tokens.append(.elapsed(unit, width))
            }
            index += 1
        }
        // Adjacent quoted literals must share one ICU quote pair: 'a''l' means
        // a literal apostrophe, whereas 'al' means the two letters.
        return tokens.reduce(into: []) { result, token in
            if case .literal(let text) = token, case .literal(let previous) = result.last {
                result[result.count - 1] = .literal(previous + text)
            } else { result.append(token) }
        }
    }

    /// Whether the `m` run at `index` means minutes: it follows hours or precedes seconds.
    static func isMinute(at index: Int, in tokens: [DateToken]) -> Bool {
        let previous = tokens[..<index].last { !$0.isLiteral }
        let next = tokens[(index + 1)...].first { !$0.isLiteral }
        switch previous {
        case .run("h", _), .elapsed("h", _): return true
        default: break
        }
        switch next {
        case .run("s", _), .elapsed("s", _): return true
        default: return false
        }
    }

    static func icuPattern(for tokens: [DateToken]) -> String {
        let usesTwelveHourClock = tokens.contains(.amPM)
        var pattern = ""
        for (index, token) in tokens.enumerated() {
            switch token {
            case .run(let unit, let count):
                switch unit {
                case "y":
                    pattern += count <= 2 ? "yy" : "yyyy"
                case "m":
                    if isMinute(at: index, in: tokens) {
                        pattern += count == 1 ? "m" : "mm"
                    } else {
                        pattern += String(repeating: "M", count: min(count, 5))
                    }
                case "d":
                    pattern += ["d", "dd", "EEE"][safe: count - 1] ?? "EEEE"
                case "h":
                    pattern += String(repeating: usesTwelveHourClock ? "h" : "H", count: min(count, 2))
                case "s":
                    pattern += count == 1 ? "s" : "ss"
                default:
                    break
                }
            case .literal(let literal):
                pattern += quotedForICU(literal)
            case .amPM:
                pattern += "a"
            case .fraction(let digits):
                pattern += "." + String(repeating: "S", count: digits)
            case .elapsed:
                break
            }
        }
        return pattern
    }

    private static func quotedForICU(_ literal: String) -> String {
        guard literal.contains(where: { $0.isLetter || $0 == "'" }) else { return literal }
        return "'" + literal.replacing("'", with: "''") + "'"
    }

    private static func padded(_ value: Double, width: Int) -> String {
        let whole = Int64(exactly: value.rounded(.down)) ?? 0
        return whole.formatted(.number.grouping(.never).precision(.integerLength(max(width, 1)...)))
    }

    // MARK: - Built-in Formats

    /// Built-in formats Excel draws in the system's short date style.
    private static let localeDateFormatIDs: Set<Int> = [14, 27, 28, 29, 30, 31, 34, 35, 36, 50, 51, 52, 53, 54, 55, 56, 57, 58]
    /// Built-in East Asian time formats, drawn in the system's time style.
    private static let localeTimeFormatIDs: Set<Int> = [32, 33]

    private static let builtinFormatCodes: [Int: String] = [
        1: "0",
        2: "0.00",
        3: "#,##0",
        4: "#,##0.00",
        5: "$#,##0_);($#,##0)",
        6: "$#,##0_);[Red]($#,##0)",
        7: "$#,##0.00_);($#,##0.00)",
        8: "$#,##0.00_);[Red]($#,##0.00)",
        9: "0%",
        10: "0.00%",
        11: "0.00E+00",
        12: "# ?/?",
        13: "# ??/??",
        15: "d-mmm-yy",
        16: "d-mmm",
        17: "mmm-yy",
        18: "h:mm AM/PM",
        19: "h:mm:ss AM/PM",
        20: "h:mm",
        21: "h:mm:ss",
        37: "#,##0 ;(#,##0)",
        38: "#,##0 ;[Red](#,##0)",
        39: "#,##0.00;(#,##0.00)",
        40: "#,##0.00;[Red](#,##0.00)",
        41: #"_(* #,##0_);_(* \(#,##0\);_(* "-"_);_(@_)"#,
        42: #"_("$"* #,##0_);_("$"* \(#,##0\);_("$"* "-"_);_(@_)"#,
        43: #"_(* #,##0.00_);_(* \(#,##0.00\);_(* "-"??_);_(@_)"#,
        44: #"_("$"* #,##0.00_);_("$"* \(#,##0.00\);_("$"* "-"??_);_(@_)"#,
        45: "mm:ss",
        46: "[h]:mm:ss",
        47: "mmss.0",
        48: "##0.0E+0",
        49: "@"
    ]
}

private extension ExcelValueFormatter.DateToken {
    nonisolated var isLiteral: Bool {
        if case .literal = self { return true }
        return false
    }
}

private extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
