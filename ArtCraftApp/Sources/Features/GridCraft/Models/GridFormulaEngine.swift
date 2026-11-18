import Foundation

private struct FormulaCellAddress: Hashable {
    let row: Int
    let column: Int
    var sheetName: String? = nil
}

struct GridFormulaSheet {
    let name: String
    let cells: [[String]]
}

private indirect enum FormulaValue {
    case number(Double)
    case text(String)
    case boolean(Bool)
    case blank
    case cell(FormulaValue)
    case range([FormulaCellAddress])
    case error(String)
}

final class GridFormulaEngine {
    private let cells: [[String]]
    private let sheets: [GridFormulaSheet]
    private let currentSheetName: String?
    private var activeCells = Set<FormulaCellAddress>()
    private var resolvedCells: [FormulaCellAddress: FormulaValue] = [:]

    init(cells: [[String]], sheets: [GridFormulaSheet] = [], currentSheetName: String? = nil) {
        self.cells = cells
        self.sheets = sheets
        self.currentSheetName = currentSheetName
    }

    func displayValue(row: Int, column: Int) -> String {
        resolve(FormulaCellAddress(row: row, column: column)).displayString
    }

    private func resolve(_ address: FormulaCellAddress) -> FormulaValue {
        if let cached = resolvedCells[address] { return cached }
        let sourceCells: [[String]]
        if let sheetName = address.sheetName,
           sheetName.caseInsensitiveCompare(currentSheetName ?? "") != .orderedSame {
            guard let sheet = sheets.first(where: { $0.name.caseInsensitiveCompare(sheetName) == .orderedSame }) else {
                return .error("#REF!")
            }
            sourceCells = sheet.cells
        } else {
            sourceCells = cells
        }
        guard sourceCells.indices.contains(address.row), sourceCells[address.row].indices.contains(address.column) else {
            return .error("#REF!")
        }
        let raw = sourceCells[address.row][address.column]
        guard raw.hasPrefix("=") else {
            let value: FormulaValue
            if raw.isEmpty { value = .blank }
            else if let number = Double(raw) { value = .number(number) }
            else if raw.uppercased() == "TRUE" { value = .boolean(true) }
            else if raw.uppercased() == "FALSE" { value = .boolean(false) }
            else { value = .text(raw) }
            resolvedCells[address] = value
            return value
        }
        guard activeCells.insert(address).inserted else { return .error("#CIRC!") }
        defer { activeCells.remove(address) }
        let parser = FormulaParser(String(raw.dropFirst())) { [weak self] cell in
            guard var engine = self else { return .error("#REF!") }
            return engine.resolve(cell)
        }
        let value = parser.evaluate()
        resolvedCells[address] = value
        return value
    }
}

private extension FormulaValue {
    var displayString: String {
        switch self {
        case .number(let value):
            guard value.isFinite else { return "#NUM!" }
            return value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.15g", value)
        case .text(let value): return value
        case .boolean(let value): return value ? "TRUE" : "FALSE"
        case .blank: return ""
        case .cell(let value): return value.displayString
        case .range: return "#VALUE!"
        case .error(let message): return message
        }
    }
}

private final class FormulaParser {
    private let characters: [Character]
    private let resolveCell: (FormulaCellAddress) -> FormulaValue
    private var cursor = 0

    init(_ formula: String, resolveCell: @escaping (FormulaCellAddress) -> FormulaValue) {
        characters = Array(formula)
        self.resolveCell = resolveCell
    }

    func evaluate() -> FormulaValue {
        let value = parseComparison()
        skipSpaces()
        return cursor == characters.count ? value : .error("#VALUE!")
    }

    private func parseComparison() -> FormulaValue {
        var left = parseConcatenation()
        while true {
            skipSpaces()
            let op: String
            if consume("<=") { op = "<=" }
            else if consume(">=") { op = ">=" }
            else if consume("<>") { op = "<>" }
            else if consume("=") { op = "=" }
            else if consume("<") { op = "<" }
            else if consume(">") { op = ">" }
            else { break }
            left = compare(left, parseConcatenation(), op)
        }
        return left
    }

    private func parseConcatenation() -> FormulaValue {
        var left = parseAdditive()
        while consume("&") {
            let right = parseAdditive()
            if case .error = left { continue }
            if case .error = right { left = right; continue }
            left = .text(left.stringValue + right.stringValue)
        }
        return left
    }

    private func parseAdditive() -> FormulaValue {
        var left = parseMultiplicative()
        while true {
            if consume("+") { left = arithmetic(left, parseMultiplicative(), +) }
            else if consume("-") { left = arithmetic(left, parseMultiplicative(), -) }
            else { return left }
        }
    }

    private func parseMultiplicative() -> FormulaValue {
        var left = parsePower()
        while true {
            if consume("*") { left = arithmetic(left, parsePower(), *) }
            else if consume("/") {
                let right = parsePower()
                if let error = firstError(left, right) { left = error }
                else if let divisor = numericValue(right), divisor == 0 { left = .error("#DIV/0!") }
                else if let dividend = numericValue(left), let divisor = numericValue(right) { left = finiteOrError(dividend / divisor) }
                else { left = .error("#VALUE!") }
            } else { return left }
        }
    }

    private func parsePower() -> FormulaValue {
        let left = parseUnary()
        guard consume("^") else { return left }
        return arithmetic(left, parsePower(), pow)
    }

    private func parseUnary() -> FormulaValue {
        if consume("+") { return numericValue(parseUnary()).map(FormulaValue.number) ?? .error("#VALUE!") }
        if consume("-") {
            let value = parseUnary()
            if let error = errorValue(value) { return error }
            return numericValue(value).map { finiteOrError(-$0) } ?? .error("#VALUE!")
        }
        var value = parsePrimary()
        while consume("%") {
            if let error = errorValue(value) { return error }
            guard let number = numericValue(value) else { return .error("#VALUE!") }
            value = finiteOrError(number / 100)
        }
        return value
    }

    private func parsePrimary() -> FormulaValue {
        skipSpaces()
        if consume("(") {
            let value = parseComparison()
            guard consume(")") else { return .error("#VALUE!") }
            return value
        }
        if peek() == "\"" { return parseString() }
        if let number = parseNumber() { return .number(number) }
        if peek() == "'" {
            guard let sheetName = parseQuotedSheetName(), consume("!"),
                  let cellName = parseName(), let address = parseCellAddress(cellName) else { return .error("#REF!") }
            return parseCellOrRange(FormulaCellAddress(row: address.row, column: address.column, sheetName: sheetName))
        }
        guard let name = parseName() else { return .error("#VALUE!") }
        skipSpaces()
        if consume("(") { return parseFunction(name) }
        if consume("!") {
            guard let cellName = parseName(), let address = parseCellAddress(cellName) else { return .error("#REF!") }
            return parseCellOrRange(FormulaCellAddress(row: address.row, column: address.column, sheetName: name))
        }
        if name.uppercased() == "TRUE" { return .boolean(true) }
        if name.uppercased() == "FALSE" { return .boolean(false) }
        guard let first = parseCellAddress(name) else { return .error("#NAME?") }
        return parseCellOrRange(first)
    }

    private func parseCellOrRange(_ first: FormulaCellAddress) -> FormulaValue {
        if consume(":") {
            guard let secondName = parseName(), let parsedSecond = parseCellAddress(secondName) else { return .error("#REF!") }
            let second = FormulaCellAddress(row: parsedSecond.row, column: parsedSecond.column, sheetName: first.sheetName)
            let minRow = min(first.row, second.row)
            let maxRow = max(first.row, second.row)
            let minColumn = min(first.column, second.column)
            let maxColumn = max(first.column, second.column)
            guard maxRow - minRow < 10_000, maxColumn - minColumn < 256,
                  (maxRow - minRow + 1) * (maxColumn - minColumn + 1) <= 100_000 else { return .error("#NUM!") }
            var addresses: [FormulaCellAddress] = []
            for row in minRow...maxRow {
                for column in minColumn...maxColumn {
                    addresses.append(FormulaCellAddress(row: row, column: column, sheetName: first.sheetName))
                }
            }
            return .range(addresses)
        }
        return .cell(resolveCell(first))
    }

    private func parseQuotedSheetName() -> String? {
        guard peek() == "'" else { return nil }
        cursor += 1
        var value = ""
        while cursor < characters.count {
            let character = characters[cursor]
            cursor += 1
            if character == "'" {
                if peek() == "'" {
                    value.append("'")
                    cursor += 1
                } else {
                    return value
                }
            } else {
                value.append(character)
            }
        }
        return nil
    }

    private func parseFunction(_ rawName: String) -> FormulaValue {
        let name = rawName.uppercased()
        var arguments: [FormulaValue] = []
        if !consume(")") {
            repeat {
                arguments.append(parseComparison())
                if consume(")") { break }
                guard consume(",") || consume(";") else { return .error("#VALUE!") }
            } while cursor < characters.count
            if characters[safe: cursor - 1] != ")" { return .error("#VALUE!") }
        }

        if !["IF", "IFERROR", "COUNT", "COUNTA", "COUNTBLANK", "COUNTIF", "COUNTIFS", "SUMIF", "SUMIFS", "AVERAGEIF", "AVERAGEIFS", "ISNUMBER", "ISTEXT", "ISBLANK", "ISERROR", "ISLOGICAL", "ISNONTEXT", "INDEX", "MATCH", "VLOOKUP", "HLOOKUP", "XLOOKUP"].contains(name),
           let error = firstArgumentError(arguments) { return error }

        switch name {
        case "SUM":
            return aggregate(arguments, operation: .sum)
        case "AVERAGE":
            return aggregate(arguments, operation: .average)
        case "MIN":
            return aggregate(arguments, operation: .minimum)
        case "MAX":
            return aggregate(arguments, operation: .maximum)
        case "COUNT":
            return .number(Double(numericArguments(arguments).count))
        case "COUNTA":
            return .number(Double(nonemptyArgumentCount(arguments)))
        case "COUNTBLANK":
            guard arguments.count == 1, let values = criteriaValues(arguments[0]) else { return .error("#VALUE!") }
            return .number(Double(values.filter { value in
                if case .blank = value { return true }
                if case .text(let text) = value { return text.isEmpty }
                return false
            }.count))
        case "COUNTIF", "SUMIF", "AVERAGEIF":
            guard (2...3).contains(arguments.count), let criteriaRange = criteriaValues(arguments[0]) else { return .error("#VALUE!") }
            let resultValues: [FormulaValue]
            if arguments.count == 3 {
                guard let values = criteriaValues(arguments[2]), values.count == criteriaRange.count else { return .error("#VALUE!") }
                resultValues = values
            } else {
                resultValues = criteriaRange
            }
            let selected = zip(criteriaRange, resultValues).compactMap { value, result in
                matchesCriterion(value, arguments[1]) ? result : nil
            }
            if name == "COUNTIF" { return .number(Double(selected.count)) }
            let numbers = selected.compactMap(numericValue)
            if name == "SUMIF" { return finiteOrError(numbers.reduce(0, +)) }
            return numbers.isEmpty ? .error("#DIV/0!") : finiteOrError(numbers.reduce(0, +) / Double(numbers.count))
        case "COUNTIFS":
            guard !arguments.isEmpty, arguments.count.isMultiple(of: 2) else { return .error("#VALUE!") }
            let pairs = stride(from: 0, to: arguments.count, by: 2).compactMap { index -> ([FormulaValue], FormulaValue)? in
                guard let values = criteriaValues(arguments[index]) else { return nil }
                return (values, arguments[index + 1])
            }
            guard pairs.count == arguments.count / 2, let first = pairs.first,
                  pairs.allSatisfy({ $0.0.count == first.0.count }) else { return .error("#VALUE!") }
            let count = first.0.indices.filter { index in
                pairs.allSatisfy { matchesCriterion($0.0[index], $0.1) }
            }.count
            return .number(Double(count))
        case "SUMIFS", "AVERAGEIFS":
            guard arguments.count >= 3, arguments.count % 2 == 1,
                  let resultValues = criteriaValues(arguments[0]) else { return .error("#VALUE!") }
            var pairs: [([FormulaValue], FormulaValue)] = []
            for index in stride(from: 1, to: arguments.count, by: 2) {
                guard let values = criteriaValues(arguments[index]), values.count == resultValues.count else { return .error("#VALUE!") }
                pairs.append((values, arguments[index + 1]))
            }
            var numbers: [Double] = []
            for index in resultValues.indices where pairs.allSatisfy({ matchesCriterion($0.0[index], $0.1) }) {
                if let number = numericValue(resultValues[index]) { numbers.append(number) }
            }
            if name == "SUMIFS" { return finiteOrError(numbers.reduce(0, +)) }
            return numbers.isEmpty ? .error("#DIV/0!") : finiteOrError(numbers.reduce(0, +) / Double(numbers.count))
        case "PRODUCT":
            return aggregate(arguments, operation: .product)
        case "SUMPRODUCT":
            guard !arguments.isEmpty else { return .error("#VALUE!") }
            let arrays = arguments.compactMap(criteriaValues)
            guard arrays.count == arguments.count, let first = arrays.first,
                  arrays.allSatisfy({ $0.count == first.count }) else { return .error("#VALUE!") }
            var total = 0.0
            for index in first.indices {
                var product = 1.0
                for array in arrays {
                    guard let number = numericValue(array[index]) else { product = 0; break }
                    product *= number
                }
                total += product
            }
            return finiteOrError(total)
        case "MEDIAN":
            let values = numericArguments(arguments).sorted()
            guard !values.isEmpty else { return .error("#NUM!") }
            let middle = values.count / 2
            return finiteOrError(values.count.isMultiple(of: 2) ? (values[middle - 1] + values[middle]) / 2 : values[middle])
        case "LARGE", "SMALL":
            guard arguments.count == 2, let rank = numericValue(arguments[1]), rank >= 1,
                  rank.rounded() == rank, rank <= 100_000 else { return .error("#NUM!") }
            let values = numericArguments([arguments[0]]).sorted()
            guard Int(rank) <= values.count else { return .error("#NUM!") }
            return .number(name == "LARGE" ? values[values.count - Int(rank)] : values[Int(rank) - 1])
        case "ABS":
            guard arguments.count == 1, let value = numericValue(arguments[0]) else { return .error("#VALUE!") }
            return finiteOrError(abs(value))
        case "SQRT":
            guard arguments.count == 1, let value = numericValue(arguments[0]), value >= 0 else { return .error("#NUM!") }
            return finiteOrError(sqrt(value))
        case "POWER":
            guard arguments.count == 2, let base = numericValue(arguments[0]), let exponent = numericValue(arguments[1]) else { return .error("#VALUE!") }
            return finiteOrError(pow(base, exponent))
        case "ROUND", "ROUNDUP", "ROUNDDOWN":
            guard arguments.count == 2, let value = numericValue(arguments[0]), let places = numericValue(arguments[1]), abs(places) <= 12 else { return .error("#VALUE!") }
            let factor = pow(10, places)
            let scaled = value * factor
            let rounded: Double
            if name == "ROUNDUP" { rounded = scaled.rounded(.awayFromZero) }
            else if name == "ROUNDDOWN" { rounded = scaled.rounded(.towardZero) }
            else { rounded = scaled.rounded(.toNearestOrAwayFromZero) }
            return finiteOrError(rounded / factor)
        case "INT":
            guard arguments.count == 1, let value = numericValue(arguments[0]) else { return .error("#VALUE!") }
            return finiteOrError(floor(value))
        case "MOD":
            guard arguments.count == 2, let value = numericValue(arguments[0]), let divisor = numericValue(arguments[1]) else { return .error("#VALUE!") }
            guard divisor != 0 else { return .error("#DIV/0!") }
            return finiteOrError(value - divisor * floor(value / divisor))
        case "IF":
            guard (2...3).contains(arguments.count) else { return .error("#VALUE!") }
            if let error = errorValue(arguments[0]) { return error }
            return truthy(arguments[0]) ? arguments[1] : (arguments.count == 3 ? arguments[2] : .boolean(false))
        case "IFERROR":
            guard arguments.count == 2 else { return .error("#VALUE!") }
            return errorValue(arguments[0]) == nil ? arguments[0] : arguments[1]
        case "INDEX":
            guard (2...3).contains(arguments.count),
                  case .range(let addresses) = arguments[0],
                  let rowNumber = numericValue(arguments[1]), rowNumber >= 1 else { return .error("#VALUE!") }
            let rows = (addresses.map(\.row).max() ?? -1) - (addresses.map(\.row).min() ?? 0) + 1
            let columns = (addresses.map(\.column).max() ?? -1) - (addresses.map(\.column).min() ?? 0) + 1
            let columnNumber = arguments.count == 3 ? (numericValue(arguments[2]) ?? 0) : 1
            guard columnNumber >= 1, rowNumber.rounded() == rowNumber, columnNumber.rounded() == columnNumber else { return .error("#VALUE!") }
            guard rowNumber <= Double(rows), columnNumber <= Double(columns) else { return .error("#REF!") }
            let offset = (Int(rowNumber) - 1) * columns + Int(columnNumber) - 1
            guard addresses.indices.contains(offset) else { return .error("#REF!") }
            return .cell(resolveCell(addresses[offset]))
        case "MATCH":
            guard (2...3).contains(arguments.count),
                  let values = lookupValues(arguments[1]), !values.isEmpty,
                  let modeValue = arguments.count == 3 ? numericValue(arguments[2]) : 1,
                  modeValue == -1 || modeValue == 0 || modeValue == 1 else { return .error("#N/A") }
            guard values.count == 1 || values.allSatisfy({ $0.0.row == values[0].0.row }) || values.allSatisfy({ $0.0.column == values[0].0.column }) else { return .error("#N/A") }
            if let index = lookupIndex(arguments[0], in: values.map(\.1), mode: Int(modeValue)) { return .number(Double(index + 1)) }
            return .error("#N/A")
        case "VLOOKUP", "HLOOKUP":
            guard (3...4).contains(arguments.count), case .range(let addresses) = arguments[1],
                  let indexValue = numericValue(arguments[2]), indexValue >= 1, indexValue.rounded() == indexValue else { return .error("#VALUE!") }
            let minRow = addresses.map(\.row).min() ?? 0
            let maxRow = addresses.map(\.row).max() ?? -1
            let minColumn = addresses.map(\.column).min() ?? 0
            let maxColumn = addresses.map(\.column).max() ?? -1
            let rowCount = maxRow - minRow + 1
            let columnCount = maxColumn - minColumn + 1
            let vertical = name == "VLOOKUP"
            let lookupSheet = addresses.first?.sheetName
            let lookupCount = vertical ? rowCount : columnCount
            let returnCount = vertical ? columnCount : rowCount
            guard rowCount > 0, columnCount > 0, indexValue <= Double(returnCount) else { return .error("#REF!") }
            let approximate = arguments.count < 4 || (truthy(arguments[3]) && numericValue(arguments[3]) != 0)
            var lookupValuesInTable: [FormulaValue] = []
            var resultAddresses: [FormulaCellAddress] = []
            for offset in 0..<lookupCount {
                let row = vertical ? minRow + offset : minRow + Int(indexValue) - 1
                let column = vertical ? minColumn : minColumn + offset
                lookupValuesInTable.append(resolveCell(FormulaCellAddress(row: row, column: column, sheetName: lookupSheet)))
                let resultRow = vertical ? minRow + offset : minRow + Int(indexValue) - 1
                let resultColumn = vertical ? minColumn + Int(indexValue) - 1 : minColumn + offset
                resultAddresses.append(FormulaCellAddress(row: resultRow, column: resultColumn, sheetName: lookupSheet))
            }
            let mode = approximate ? 1 : 0
            guard let match = lookupIndex(arguments[0], in: lookupValuesInTable, mode: mode) else { return .error("#N/A") }
            return .cell(resolveCell(resultAddresses[match]))
        case "XLOOKUP":
            guard (3...6).contains(arguments.count),
                  let lookupAddresses = lookupValues(arguments[1]),
                  let returnAddresses = lookupValues(arguments[2]),
                  !lookupAddresses.isEmpty, lookupAddresses.count == returnAddresses.count,
                  let lookupModeValue = arguments.count >= 5 ? numericValue(arguments[4]) : 0,
                  let searchModeValue = arguments.count >= 6 ? numericValue(arguments[5]) : 1,
                  lookupModeValue.rounded() == lookupModeValue,
                  searchModeValue.rounded() == searchModeValue,
                  [-1.0, 0.0, 1.0, 2.0].contains(lookupModeValue),
                  [-1.0, 1.0].contains(searchModeValue) else { return .error("#VALUE!") }
            let sought = arguments[0]
            let mode = Int(lookupModeValue)
            let indices = searchModeValue == -1
                ? Array(lookupAddresses.indices.reversed())
                : Array(lookupAddresses.indices)
            var match: Int?
            var nearest: FormulaValue?
            for index in indices {
                let candidate = lookupAddresses[index].1
                if mode == 0 && valuesEqual(sought, candidate) {
                    match = index
                    break
                }
                if mode == 2 && wildcardMatches(candidate.stringValue, pattern: sought.stringValue) {
                    match = index
                    break
                }
                if mode == -1 && compare(candidate, sought, "<=").booleanValue {
                    if let current = nearest {
                        if compare(candidate, current, ">").booleanValue { nearest = candidate; match = index }
                    } else { nearest = candidate; match = index }
                } else if mode == 1 && compare(candidate, sought, ">=").booleanValue {
                    if let current = nearest {
                        if compare(candidate, current, "<").booleanValue { nearest = candidate; match = index }
                    } else { nearest = candidate; match = index }
                }
            }
            guard let match else {
                return arguments.count >= 4 ? arguments[3] : .error("#N/A")
            }
            return .cell(resolveCell(returnAddresses[match].0))
        case "AND", "OR":
            guard !arguments.isEmpty else { return .error("#VALUE!") }
            for argument in arguments { if let error = errorValue(argument) { return error } }
            let values = arguments.flatMap(flattenedValues)
            return .boolean(name == "AND" ? values.allSatisfy(truthy) : values.contains(where: truthy))
        case "NOT":
            guard arguments.count == 1 else { return .error("#VALUE!") }
            if let error = errorValue(arguments[0]) { return error }
            return .boolean(!truthy(arguments[0]))
        case "CONCAT", "CONCATENATE":
            let joined = arguments.flatMap(flattenedValues).map(\.stringValue).joined()
            return joined.count <= 32_767 ? .text(joined) : .error("#VALUE!")
        case "TEXTJOIN":
            guard arguments.count >= 3 else { return .error("#VALUE!") }
            let delimiter = arguments[0].stringValue
            let ignoreEmpty = truthy(arguments[1])
            let pieces = arguments.dropFirst(2).flatMap(flattenedValues).map(\.stringValue)
            let joined = (ignoreEmpty ? pieces.filter { !$0.isEmpty } : pieces).joined(separator: delimiter)
            return joined.count <= 32_767 ? .text(joined) : .error("#VALUE!")
        case "VALUE":
            guard arguments.count == 1 else { return .error("#VALUE!") }
            let text = arguments[0].stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Double(text) else { return .error("#VALUE!") }
            return finiteOrError(value)
        case "SUBSTITUTE":
            guard (3...4).contains(arguments.count) else { return .error("#VALUE!") }
            let source = arguments[0].stringValue
            let oldText = arguments[1].stringValue
            let newText = arguments[2].stringValue
            guard !oldText.isEmpty else { return .text(source) }
            guard arguments.count == 4 else { return .text(source.replacingOccurrences(of: oldText, with: newText)) }
            guard let instance = numericValue(arguments[3]), instance >= 1, instance.rounded() == instance else { return .error("#VALUE!") }
            let mutable = NSMutableString(string: source)
            var searchRange = NSRange(location: 0, length: mutable.length)
            var foundRanges: [NSRange] = []
            while searchRange.length > 0 {
                let found = mutable.range(of: oldText, options: [], range: searchRange)
                guard found.location != NSNotFound else { break }
                foundRanges.append(found)
                let next = NSMaxRange(found)
                searchRange = NSRange(location: next, length: mutable.length - next)
            }
            guard foundRanges.indices.contains(Int(instance) - 1) else { return .text(source) }
            mutable.replaceCharacters(in: foundRanges[Int(instance) - 1], with: newText)
            return .text(mutable as String)
        case "SEARCH", "FIND":
            guard (2...3).contains(arguments.count) else { return .error("#VALUE!") }
            let needle = arguments[0].stringValue
            let haystack = arguments[1].stringValue as NSString
            let start = arguments.count == 3 ? (numericValue(arguments[2]) ?? 0) : 1
            guard start >= 1, start.rounded() == start, start <= Double(haystack.length + 1) else { return .error("#VALUE!") }
            let location = Int(start) - 1
            let range = NSRange(location: location, length: haystack.length - location)
            let options: NSString.CompareOptions = name == "SEARCH" ? [.caseInsensitive] : []
            let found = haystack.range(of: needle, options: options, range: range)
            return found.location == NSNotFound ? .error("#VALUE!") : .number(Double(found.location + 1))
        case "REPLACE":
            guard arguments.count == 4, let start = numericValue(arguments[1]), let count = numericValue(arguments[2]),
                  start >= 1, count >= 0, start.rounded() == start, count.rounded() == count else { return .error("#VALUE!") }
            let source = arguments[0].stringValue as NSString
            guard start <= Double(source.length + 1) else { return .error("#VALUE!") }
            let location = min(Int(start) - 1, source.length)
            let length = min(Int(count), source.length - location)
            return .text(source.replacingCharacters(in: NSRange(location: location, length: length), with: arguments[3].stringValue))
        case "PROPER":
            return arguments.count == 1 ? .text(arguments[0].stringValue.capitalized) : .error("#VALUE!")
        case "EXACT":
            guard arguments.count == 2 else { return .error("#VALUE!") }
            return .boolean(arguments[0].stringValue == arguments[1].stringValue)
        case "ISNUMBER", "ISTEXT", "ISBLANK", "ISERROR", "ISLOGICAL", "ISNONTEXT":
            guard arguments.count == 1 else { return .error("#VALUE!") }
            let value: FormulaValue
            if case .cell(let nested) = arguments[0] { value = nested } else { value = arguments[0] }
            switch name {
            case "ISNUMBER":
                if case .number = value { return .boolean(true) }
                return .boolean(false)
            case "ISTEXT":
                if case .text = value { return .boolean(true) }
                return .boolean(false)
            case "ISBLANK":
                if case .blank = value { return .boolean(true) }
                return .boolean(false)
            case "ISERROR":
                if case .error = value { return .boolean(true) }
                return .boolean(false)
            case "ISLOGICAL":
                if case .boolean = value { return .boolean(true) }
                return .boolean(false)
            default:
                if case .text = value { return .boolean(false) }
                return .boolean(true)
            }
        case "N":
            guard arguments.count == 1 else { return .error("#VALUE!") }
            switch arguments[0] {
            case .number(let number): return .number(number)
            case .boolean(let value): return .number(value ? 1 : 0)
            case .cell(let nested): return numericValue(nested).map(FormulaValue.number) ?? .number(0)
            default: return .number(0)
            }
        case "T":
            guard arguments.count == 1 else { return .error("#VALUE!") }
            if case .text(let value) = arguments[0] { return .text(value) }
            if case .cell(.text(let value)) = arguments[0] { return .text(value) }
            return .text("")
        case "CHAR", "CODE":
            guard arguments.count == 1 else { return .error("#VALUE!") }
            if name == "CHAR" {
                guard let number = numericValue(arguments[0]), number >= 1, number <= 255, number.rounded() == number,
                      let scalar = UnicodeScalar(Int(number)) else { return .error("#VALUE!") }
                return .text(String(Character(scalar)))
            }
            guard let scalar = arguments[0].stringValue.unicodeScalars.first else { return .error("#VALUE!") }
            return .number(Double(scalar.value))
        case "LEN":
            guard arguments.count == 1 else { return .error("#VALUE!") }
            return .number(Double(arguments[0].stringValue.count))
        case "LEFT", "RIGHT":
            guard (1...2).contains(arguments.count), let count = arguments.count == 2 ? numericValue(arguments[1]) : 1, count >= 0, count <= 100_000 else { return .error("#VALUE!") }
            let string = Array(arguments[0].stringValue)
            let amount = min(Int(count), string.count)
            return .text(name == "LEFT" ? String(string.prefix(amount)) : String(string.suffix(amount)))
        case "MID":
            guard arguments.count == 3, let start = numericValue(arguments[1]), let count = numericValue(arguments[2]), start >= 1, count >= 0, start <= 100_000, count <= 100_000 else { return .error("#VALUE!") }
            let string = Array(arguments[0].stringValue)
            let lower = min(Int(start) - 1, string.count)
            return .text(String(string[lower..<min(lower + Int(count), string.count)]))
        case "LOWER": return arguments.count == 1 ? .text(arguments[0].stringValue.lowercased()) : .error("#VALUE!")
        case "UPPER": return arguments.count == 1 ? .text(arguments[0].stringValue.uppercased()) : .error("#VALUE!")
        case "TRIM":
            guard arguments.count == 1 else { return .error("#VALUE!") }
            return .text(arguments[0].stringValue.split(whereSeparator: \.isWhitespace).joined(separator: " "))
        default: return .error("#NAME?")
        }
    }

    private enum AggregateOperation { case sum, average, minimum, maximum, product }

    private func aggregate(_ arguments: [FormulaValue], operation: AggregateOperation) -> FormulaValue {
        let values = numericArguments(arguments)
        if values.isEmpty {
            switch operation {
            case .sum: return .number(0)
            case .product: return .number(1)
            case .minimum, .maximum: return .number(0)
            case .average: return .error("#DIV/0!")
            }
        }
        switch operation {
        case .sum: return finiteOrError(values.reduce(0, +))
        case .average: return finiteOrError(values.reduce(0, +) / Double(values.count))
        case .minimum: return .number(values.min() ?? 0)
        case .maximum: return .number(values.max() ?? 0)
        case .product: return finiteOrError(values.reduce(1, *))
        }
    }

    private func numericArguments(_ arguments: [FormulaValue]) -> [Double] {
        var numbers: [Double] = []
        func append(_ value: FormulaValue, fromReference: Bool) {
            switch value {
            case .cell(let referenced): append(referenced, fromReference: true)
            case .range(let addresses):
                for address in addresses { append(resolveCell(address), fromReference: true) }
            case .number(let number): numbers.append(number)
            case .text(let text): if !fromReference, let number = Double(text) { numbers.append(number) }
            case .boolean(let value): if !fromReference { numbers.append(value ? 1 : 0) }
            case .blank: break
            case .error, .cell, .range: break
            }
        }
        arguments.forEach { append($0, fromReference: false) }
        return numbers
    }

    private func nonemptyArgumentCount(_ arguments: [FormulaValue]) -> Int {
        var count = 0
        func append(_ value: FormulaValue, fromReference: Bool) {
            switch value {
            case .cell(let referenced): append(referenced, fromReference: true)
            case .range(let addresses): for address in addresses { append(resolveCell(address), fromReference: true) }
            case .blank: break
            case .error: count += 1
            case .text(let text): if !text.isEmpty { count += 1 }
            case .number, .boolean: count += 1
            }
        }
        arguments.forEach { append($0, fromReference: false) }
        return count
    }

    private func firstArgumentError(_ arguments: [FormulaValue]) -> FormulaValue? {
        for argument in arguments {
            if let error = errorValue(argument) { return error }
            if case .range(let addresses) = argument {
                for address in addresses {
                    if let error = errorValue(resolveCell(address)) { return error }
                }
            }
        }
        return nil
    }

    private func flattenedValues(_ value: FormulaValue) -> [FormulaValue] {
        switch value {
        case .cell(let nested): return [nested]
        case .range(let addresses): return addresses.map(resolveCell)
        default: return [value]
        }
    }

    private func lookupValues(_ value: FormulaValue) -> [(FormulaCellAddress, FormulaValue)]? {
        switch value {
        case .range(let addresses): return addresses.map { ($0, resolveCell($0)) }
        case .cell: return nil
        default: return nil
        }
    }

    private func criteriaValues(_ value: FormulaValue) -> [FormulaValue]? {
        switch value {
        case .range(let addresses): return addresses.map(resolveCell)
        case .cell(let nested): return [nested]
        case .error: return nil
        default: return [value]
        }
    }

    private func matchesCriterion(_ value: FormulaValue, _ criterion: FormulaValue) -> Bool {
        let text = criterion.stringValue
        let operators = [">=", "<=", "<>", ">", "<", "="]
        let operation = operators.first(where: { text.hasPrefix($0) }) ?? "="
        let soughtText = operators.contains(where: { text.hasPrefix($0) }) ? String(text.dropFirst(operation.count)) : text
        let sought: FormulaValue = Double(soughtText).map(FormulaValue.number) ?? .text(soughtText)
        if value.stringValue.isEmpty && soughtText.isEmpty { return operation == "=" }
        if let actualError = errorValue(value) { return operation == "<>" && actualError.displayString != soughtText }
        if soughtText.contains("*") || soughtText.contains("?") {
            let matched = wildcardMatches(value.stringValue, pattern: soughtText)
            return operation == "<>" ? !matched : operation == "=" && matched
        }
        return compare(value, sought, operation).booleanValue
    }

    private func wildcardMatches(_ value: String, pattern: String) -> Bool {
        let characters = Array(pattern)
        var expression = "^"
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "~", index + 1 < characters.count {
                index += 1
                expression += NSRegularExpression.escapedPattern(for: String(characters[index]))
            } else if character == "*" {
                expression += ".*"
            } else if character == "?" {
                expression += "."
            } else {
                expression += NSRegularExpression.escapedPattern(for: String(character))
            }
            index += 1
        }
        expression += "$"
        guard let regex = try? NSRegularExpression(pattern: expression, options: [.caseInsensitive]) else { return false }
        return regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    private func lookupIndex(_ sought: FormulaValue, in values: [FormulaValue], mode: Int) -> Int? {
        if mode == 0 { return values.firstIndex(where: { valuesEqual(sought, $0) }) }
        if mode == 1 {
            var candidate: Int?
            for (index, value) in values.enumerated() {
                if compare(sought, value, ">=").booleanValue { candidate = index }
            }
            return candidate
        }
        return values.firstIndex(where: { compare(sought, $0, "<=").booleanValue })
    }

    private func valuesEqual(_ left: FormulaValue, _ right: FormulaValue) -> Bool {
        if let lhs = numericValue(left), let rhs = numericValue(right) { return lhs == rhs }
        return left.stringValue.localizedCaseInsensitiveCompare(right.stringValue) == .orderedSame
    }

    private func numericValue(_ value: FormulaValue) -> Double? {
        switch value {
        case .number(let number): return number
        case .cell(let nested): return numericValue(nested)
        case .blank: return 0
        case .boolean(let value): return value ? 1 : 0
        case .text(let value): return Double(value)
        default: return nil
        }
    }

    private func compare(_ left: FormulaValue, _ right: FormulaValue, _ operation: String) -> FormulaValue {
        if let error = firstError(left, right) { return error }
        let result: Bool
        if let lhs = numericValue(left), let rhs = numericValue(right) {
            switch operation {
            case "=": result = lhs == rhs
            case "<>": result = lhs != rhs
            case "<": result = lhs < rhs
            case ">": result = lhs > rhs
            case "<=": result = lhs <= rhs
            default: result = lhs >= rhs
            }
        } else {
            let lhs = left.stringValue.localizedLowercase
            let rhs = right.stringValue.localizedLowercase
            switch operation {
            case "=": result = lhs == rhs
            case "<>": result = lhs != rhs
            case "<": result = lhs < rhs
            case ">": result = lhs > rhs
            case "<=": result = lhs <= rhs
            default: result = lhs >= rhs
            }
        }
        return .boolean(result)
    }

    private func arithmetic(_ left: FormulaValue, _ right: FormulaValue, _ operation: (Double, Double) -> Double) -> FormulaValue {
        if let error = firstError(left, right) { return error }
        guard let lhs = numericValue(left), let rhs = numericValue(right) else { return .error("#VALUE!") }
        return finiteOrError(operation(lhs, rhs))
    }

    private func firstError(_ values: FormulaValue...) -> FormulaValue? { values.compactMap(errorValue).first }
    private func errorValue(_ value: FormulaValue) -> FormulaValue? {
        switch value {
        case .error: return value
        case .cell(let nested): return errorValue(nested)
        default: return nil
        }
    }
    private func finiteOrError(_ value: Double) -> FormulaValue { value.isFinite ? .number(value) : .error("#NUM!") }
    private func truthy(_ value: FormulaValue) -> Bool {
        switch value {
        case .boolean(let boolean): return boolean
        case .number(let number): return number != 0
        case .cell(let nested): return truthy(nested)
        case .blank: return false
        case .text(let text): return !text.isEmpty && text.uppercased() != "FALSE"
        case .range(let range): return range.count == 1 ? truthy(resolveCell(range[0])) : false
        case .error: return false
        }
    }

    private func parseString() -> FormulaValue {
        _ = consume("\"")
        var value = ""
        while cursor < characters.count {
            if consume("\"") {
                if consume("\"") { value.append("\"") }
                else { return .text(value) }
            } else { value.append(characters[cursor]); cursor += 1 }
        }
        return .error("#VALUE!")
    }

    private func parseNumber() -> Double? {
        skipSpaces()
        let start = cursor
        var sawDigit = false
        while let character = peek(), character.isNumber { sawDigit = true; cursor += 1 }
        if peek() == "." { cursor += 1; while let character = peek(), character.isNumber { sawDigit = true; cursor += 1 } }
        if !sawDigit { cursor = start; return nil }
        if peek() == "E" || peek() == "e" {
            let exponentStart = cursor
            cursor += 1
            if peek() == "+" || peek() == "-" { cursor += 1 }
            let digitStart = cursor
            while let character = peek(), character.isNumber { cursor += 1 }
            if cursor == digitStart { cursor = exponentStart }
        }
        return Double(String(characters[start..<cursor]))
    }

    private func parseName() -> String? {
        skipSpaces()
        let start = cursor
        if peek() == "$" { cursor += 1 }
        while let character = peek(), character.isLetter { cursor += 1 }
        if cursor == start || (cursor == start + 1 && characters[start] == "$" ) { cursor = start; return nil }
        if peek() == "$" { cursor += 1 }
        let digitStart = cursor
        while let character = peek(), character.isNumber { cursor += 1 }
        if cursor == digitStart {
            while let character = peek(), character.isLetter || character.isNumber || character == "_" || character == "." { cursor += 1 }
        }
        return String(characters[start..<cursor])
    }

    private func parseCellAddress(_ raw: String) -> FormulaCellAddress? {
        let value = raw.replacingOccurrences(of: "$", with: "")
        let letters = String(value.prefix { $0.isLetter }).uppercased()
        guard !letters.isEmpty, let row = Int(value.dropFirst(letters.count)), row > 0 else { return nil }
        let column = letters.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
        guard column >= 0 else { return nil }
        return FormulaCellAddress(row: row - 1, column: column)
    }

    private func consume(_ token: String) -> Bool {
        skipSpaces()
        let tokenCharacters = Array(token)
        guard cursor + tokenCharacters.count <= characters.count,
              Array(characters[cursor..<(cursor + tokenCharacters.count)]) == tokenCharacters else { return false }
        cursor += tokenCharacters.count
        return true
    }

    private func peek() -> Character? { cursor < characters.count ? characters[cursor] : nil }
    private func skipSpaces() { while peek()?.isWhitespace == true { cursor += 1 } }
}

private extension FormulaValue {
    var booleanValue: Bool {
        if case .boolean(let value) = self { return value }
        return false
    }

    var stringValue: String {
        switch self {
        case .number(let value): return value.isFinite ? (value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.15g", value)) : "#NUM!"
        case .text(let value): return value
        case .boolean(let value): return value ? "TRUE" : "FALSE"
        case .blank: return ""
        case .cell(let value): return value.stringValue
        case .range: return "#VALUE!"
        case .error(let error): return error
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
