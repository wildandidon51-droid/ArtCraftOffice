import Foundation

enum GridXlsxCodecError: Error {
    case invalidWorkbook
    case workbookTooLarge
}

struct GridXlsxSheet {
    let sheetName: String
    let cells: [[String]]
    let styles: [String: GridCellStyle] = [:]
    var charts: [GridXlsxChart] = []
}

struct GridXlsxChart {
    let sheetName: String
    let title: String
    let categoryColumn: Int
    let valueColumn: Int
    let firstDataRow: Int
    let lastDataRow: Int
    let kind: String
}

struct GridXlsxContent {
    let sheets: [GridXlsxSheet]
    var charts: [GridXlsxChart] = []
}

enum GridXlsxCodec {
    private static let maximumRows = 10_000
    private static let maximumColumns = 256
    private static let maximumCharts = 500
    private static let maximumXMLSize: UInt64 = 64_000_000
    private static let maximumArchiveSize = 100_000_000

    static func encode(title: String, sheets: [GridXlsxSheet]) throws -> Data {
        guard !sheets.isEmpty, sheets.count <= 255,
              sheets.reduce(0, { $0 + $1.charts.count }) <= maximumCharts,
              sheets.allSatisfy({ $0.cells.count <= maximumRows && ($0.cells.map(\.count).max() ?? 0) <= maximumColumns }) else {
            throw GridXlsxCodecError.workbookTooLarge
        }
        var entries: [String: Data] = [
            "[Content_Types].xml": Data(contentTypes.utf8),
            "_rels/.rels": Data(rootRelationships.utf8),
            "xl/workbook.xml": Data(workbookXML(sheets: sheets).utf8),
            "xl/_rels/workbook.xml.rels": Data(workbookRelationships(sheetCount: sheets.count).utf8),
            "xl/styles.xml": Data(stylesXML.utf8)
        ]
        entries["[Content_Types].xml"] = Data(contentTypes.replacingOccurrences(of: "<Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>", with: sheets.indices.map { "<Override PartName=\"/xl/worksheets/sheet\($0 + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>" }.joined()).utf8)
        var chartNumber = 0
        for (index, sheet) in sheets.enumerated() {
            let sheetNumber = index + 1
            entries["xl/worksheets/sheet\(sheetNumber).xml"] = Data(worksheetXML(sheet.cells, styles: sheet.styles, hasDrawing: !sheet.charts.isEmpty).utf8)
            guard !sheet.charts.isEmpty else { continue }
            let drawingPath = "xl/drawings/drawing\(sheetNumber).xml"
            var anchors = ""
            var chartRelationships = ""
            for (chartIndex, chart) in sheet.charts.enumerated() {
                chartNumber += 1
                let relationshipID = "rId\(chartIndex + 1)"
                anchors += chartAnchor(relationshipID: relationshipID, column: max(0, (sheet.cells.map(\.count).max() ?? 1) + 1), row: chartIndex * 18)
                chartRelationships += "<Relationship Id=\"\(relationshipID)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart\" Target=\"../charts/chart\(chartNumber).xml\"/>"
                entries["xl/charts/chart\(chartNumber).xml"] = Data(chartXML(chart, sheetName: safeSheetName(sheet.sheetName)).utf8)
            }
            entries[drawingPath] = Data(drawingXML(anchors).utf8)
            entries["xl/drawings/_rels/drawing\(sheetNumber).xml.rels"] = Data(xmlRelationships(chartRelationships).utf8)
            entries["xl/worksheets/_rels/sheet\(sheetNumber).xml.rels"] = Data(xmlRelationships("<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing\" Target=\"../drawings/drawing\(sheetNumber).xml\"/>").utf8)
        }
        if chartNumber > 0 {
            var overrides = ""
            for index in sheets.indices where !sheets[index].charts.isEmpty {
                overrides += "<Override PartName=\"/xl/drawings/drawing\(index + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawing+xml\"/>"
            }
            overrides += (1...chartNumber).map { "<Override PartName=\"/xl/charts/chart\($0).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/>" }.joined()
            if let contentTypes = String(data: entries["[Content_Types].xml"] ?? Data(), encoding: .utf8) {
                entries["[Content_Types].xml"] = Data(contentTypes.replacingOccurrences(of: "</Types>", with: "\(overrides)</Types>").utf8)
            }
        }
        return try OfficeOpenXMLArchive.create(entries: entries)
    }

    static func decode(_ data: Data) throws -> GridXlsxContent {
        guard data.count <= maximumArchiveSize else { throw GridXlsxCodecError.workbookTooLarge }
        let workbookXML = try OfficeOpenXMLArchive.read("xl/workbook.xml", from: data, maximumSize: maximumXMLSize)
        let relationshipsXML = try OfficeOpenXMLArchive.read("xl/_rels/workbook.xml.rels", from: data, maximumSize: maximumXMLSize)
        let workbook = WorkbookXMLParser(data: workbookXML)
        guard workbook.parse(), !workbook.sheets.isEmpty else { throw GridXlsxCodecError.invalidWorkbook }
        let relationships = RelationshipXMLParser(data: relationshipsXML)
        guard relationships.parse() else {
            throw GridXlsxCodecError.invalidWorkbook
        }
        let sharedStrings = (try? OfficeOpenXMLArchive.read("xl/sharedStrings.xml", from: data, maximumSize: maximumXMLSize))
            .flatMap { parseSharedStrings($0) } ?? []
        let styleMap = (try? OfficeOpenXMLArchive.read("xl/styles.xml", from: data, maximumSize: maximumXMLSize))
            .flatMap { parseStyles($0) } ?? [:]
        var decodedCharts: [GridXlsxChart] = []
        let decoded = try workbook.sheets.map { sheet -> GridXlsxSheet in
            guard let target = relationships.targets[sheet.relationshipID] else { throw GridXlsxCodecError.invalidWorkbook }
            let worksheetPath = normalizedWorksheetPath(target)
            let worksheetXML = try OfficeOpenXMLArchive.read(worksheetPath, from: data, maximumSize: maximumXMLSize)
            let worksheet = WorksheetXMLParser(data: worksheetXML, sharedStrings: sharedStrings, styleMap: styleMap)
            guard worksheet.parse() else { throw GridXlsxCodecError.invalidWorkbook }
            if let drawingID = worksheet.drawingRelationshipID {
                decodedCharts.append(contentsOf: decodeCharts(drawingID: drawingID, worksheetPath: worksheetPath, currentSheetName: sheet.name, from: data))
                guard decodedCharts.count <= maximumCharts else { throw GridXlsxCodecError.workbookTooLarge }
            }
            let rowCount = (worksheet.values.keys.map(\.row).max() ?? 0) + 1
            let columnCount = (worksheet.values.keys.map(\.column).max() ?? 0) + 1
            guard rowCount <= maximumRows, columnCount <= maximumColumns else { throw GridXlsxCodecError.workbookTooLarge }
            var cells = Array(repeating: Array(repeating: "", count: columnCount), count: rowCount)
            for (address, value) in worksheet.values { cells[address.row][address.column] = value }
            let styles = Dictionary(uniqueKeysWithValues: worksheet.cellStyles.compactMap { address, style in
                style.isDefault ? nil : (cellReference(row: address.row, column: address.column), style)
            })
            return GridXlsxSheet(sheetName: sheet.name, cells: cells, styles: styles)
        }
        return GridXlsxContent(sheets: decoded, charts: decodedCharts)
    }

    private static func decodeCharts(drawingID: String, worksheetPath: String, currentSheetName: String, from data: Data) -> [GridXlsxChart] {
        let worksheetDirectory = (worksheetPath as NSString).deletingLastPathComponent
        let worksheetRelationshipPath = worksheetDirectory + "/_rels/" + ((worksheetPath as NSString).lastPathComponent) + ".rels"
        guard let worksheetRelationshipsData = try? OfficeOpenXMLArchive.read(worksheetRelationshipPath, from: data, maximumSize: maximumXMLSize) else { return [] }
        let worksheetRelationships = RelationshipXMLParser(data: worksheetRelationshipsData)
        guard worksheetRelationships.parse(), let drawingTarget = worksheetRelationships.targets[drawingID],
              let drawingPath = normalizePartPath(drawingTarget, relativeTo: worksheetDirectory) else { return [] }
        guard let drawingData = try? OfficeOpenXMLArchive.read(drawingPath, from: data, maximumSize: maximumXMLSize) else { return [] }
        let drawing = DrawingXMLParser(data: drawingData)
        guard drawing.parse(), !drawing.chartRelationshipIDs.isEmpty, drawing.chartRelationshipIDs.count <= maximumCharts else { return [] }
        let drawingDirectory = (drawingPath as NSString).deletingLastPathComponent
        let drawingRelationshipPath = drawingDirectory + "/_rels/" + ((drawingPath as NSString).lastPathComponent) + ".rels"
        guard let drawingRelationshipsData = try? OfficeOpenXMLArchive.read(drawingRelationshipPath, from: data, maximumSize: maximumXMLSize) else { return [] }
        let drawingRelationships = RelationshipXMLParser(data: drawingRelationshipsData)
        guard drawingRelationships.parse() else { return [] }
        return drawing.chartRelationshipIDs.compactMap { relationshipID in
            guard let chartTarget = drawingRelationships.targets[relationshipID],
                  let chartPath = normalizePartPath(chartTarget, relativeTo: drawingDirectory),
                  let chartData = try? OfficeOpenXMLArchive.read(chartPath, from: data, maximumSize: maximumXMLSize) else { return nil }
            let parser = ChartXMLParser(data: chartData)
            guard parser.parse(), parser.chartTypeSupported, parser.seriesCount == 1, parser.formulas.count >= 2,
                  let categories = parseChartRange(parser.formulas[0]),
                  let values = parseChartRange(parser.formulas[1]),
                  categories.sheetName.caseInsensitiveCompare(currentSheetName) == .orderedSame,
                  values.sheetName.caseInsensitiveCompare(currentSheetName) == .orderedSame,
                  categories.firstRow == values.firstRow, categories.lastRow == values.lastRow,
                  categories.firstColumn == categories.lastColumn,
                  values.firstColumn == values.lastColumn,
                  categories.firstRow >= 0, categories.lastRow < maximumRows,
                  categories.firstColumn >= 0, categories.firstColumn < maximumColumns,
                  values.firstColumn >= 0, values.firstColumn < maximumColumns else { return nil }
            return GridXlsxChart(sheetName: currentSheetName, title: parser.title.isEmpty ? "Chart" : parser.title,
                                 categoryColumn: categories.firstColumn, valueColumn: values.firstColumn,
                                 firstDataRow: categories.firstRow, lastDataRow: categories.lastRow,
                                 kind: parser.kind)
        }
    }

    private static func normalizePartPath(_ target: String, relativeTo directory: String) -> String? {
        var components = target.hasPrefix("/") ? [] : directory.split(separator: "/").map(String.init)
        for component in target.split(separator: "/") {
            switch component {
            case ".": continue
            case "..":
                guard !components.isEmpty else { return nil }
                components.removeLast()
            default: components.append(String(component))
            }
        }
        let path = components.joined(separator: "/")
        return path.hasPrefix("xl/") ? path : nil
    }

    private static func parseChartRange(_ formula: String) -> (sheetName: String, firstColumn: Int, firstRow: Int, lastColumn: Int, lastRow: Int)? {
        let pattern = #"^'((?:[^']|'')+)'!\$?([A-Z]{1,3})\$?([1-9][0-9]*):\$?([A-Z]{1,3})\$?([1-9][0-9]*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: formula, range: NSRange(formula.startIndex..., in: formula)),
              let sheetRange = Range(match.range(at: 1), in: formula),
              let firstColumnRange = Range(match.range(at: 2), in: formula),
              let firstRowRange = Range(match.range(at: 3), in: formula),
              let lastColumnRange = Range(match.range(at: 4), in: formula),
              let lastRowRange = Range(match.range(at: 5), in: formula),
              let firstRow = Int(formula[firstRowRange]), let lastRow = Int(formula[lastRowRange]) else { return nil }
        func columnIndex(_ letters: Substring) -> Int {
            letters.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
        }
        return (String(formula[sheetRange]).replacingOccurrences(of: "''", with: "'"),
                columnIndex(formula[firstColumnRange]), firstRow - 1,
                columnIndex(formula[lastColumnRange]), lastRow - 1)
    }

    private static func worksheetXML(_ cells: [[String]], styles: [String: GridCellStyle], hasDrawing: Bool) -> String {
        let nonemptyRows = cells.enumerated().filter { rowIndex, row in
            row.contains(where: { !$0.isEmpty }) || styles.keys.contains(where: { parseCellAddress($0)?.row == rowIndex })
        }
        var rowXML = ""
        for (rowIndex, row) in nonemptyRows {
            var cellXML = ""
            for (columnIndex, value) in row.enumerated() {
                let reference = cellReference(row: rowIndex, column: columnIndex)
                let cellStyle = styles[reference] ?? GridCellStyle()
                guard !value.isEmpty || !cellStyle.isDefault else { continue }
                let styleAttribute = cellStyle.isDefault ? "" : " s=\"\(styleIndex(cellStyle))\""
                if value.hasPrefix("=") {
                    let formula = escapeXML(String(value.dropFirst()))
                    cellXML += "<c r=\"\(reference)\"\(styleAttribute)><f>\(formula)</f></c>"
                } else if let number = Double(value), number.isFinite {
                    cellXML += "<c r=\"\(reference)\"\(styleAttribute)><v>\(numberXML(value, value: number))</v></c>"
                } else {
                    cellXML += "<c r=\"\(reference)\" t=\"inlineStr\"\(styleAttribute)><is><t xml:space=\"preserve\">\(escapeXML(value))</t></is></c>"
                }
            }
            rowXML += "<row r=\"\(rowIndex + 1)\">\(cellXML)</row>"
        }
        let lastRow = max(cells.count, 1) - 1
        let lastColumn = max(cells.map(\.count).max() ?? 1, 1) - 1
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><dimension ref="A1:\(cellReference(row: lastRow, column: lastColumn))"/><sheetViews><sheetView workbookViewId="0" showGridLines="1"/></sheetViews><sheetFormatPr defaultRowHeight="18"/><sheetData>\(rowXML)</sheetData><pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>\(hasDrawing ? "<drawing r:id=\"rId1\"/>" : "")</worksheet>
        """
    }

    private static func xmlRelationships(_ relationships: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(relationships)</Relationships>"
    }

    private static func drawingXML(_ anchors: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><xdr:wsDr xmlns:xdr=\"http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">\(anchors)</xdr:wsDr>"
    }

    private static func chartAnchor(relationshipID: String, column: Int, row: Int) -> String {
        "<xdr:twoCellAnchor><xdr:from><xdr:col>\(column)</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>\(row)</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from><xdr:to><xdr:col>\(column + 9)</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>\(row + 16)</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to><xdr:graphicFrame macro=\"\"><xdr:nvGraphicFramePr><xdr:cNvPr id=\"\(row + 2)\" name=\"Chart \(row / 18 + 1)\"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr><xdr:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/></xdr:xfrm><a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/chart\"><c:chart xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" r:id=\"\(relationshipID)\"/></a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/></xdr:twoCellAnchor>"
    }

    private static func chartXML(_ chart: GridXlsxChart, sheetName: String) -> String {
        let sheet = "'\(escapeXML(sheetName.replacingOccurrences(of: "'", with: "''")))'"
        let firstRow = chart.firstDataRow + 1
        let lastRow = chart.lastDataRow + 1
        let categories = "\(sheet)!$\(columnLetters(chart.categoryColumn))$\(firstRow):$\(columnLetters(chart.categoryColumn))$\(lastRow)"
        let values = "\(sheet)!$\(columnLetters(chart.valueColumn))$\(firstRow):$\(columnLetters(chart.valueColumn))$\(lastRow)"
        let title = "<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr/></a:pPr><a:r><a:rPr lang=\"en-US\"/><a:t>\(escapeXML(chart.title))</a:t></a:r><a:endParaRPr lang=\"en-US\"/></a:p></c:rich></c:tx><c:overlay val=\"0\"/></c:title>"
        let series = "<c:ser><c:idx val=\"0\"/><c:order val=\"0\"/><c:tx><c:v>\(escapeXML(chart.title))</c:v></c:tx><c:cat><c:strRef><c:f>\(categories)</c:f></c:strRef></c:cat><c:val><c:numRef><c:f>\(values)</c:f></c:numRef></c:val></c:ser>"
        let plot: String
        if chart.kind == "line" {
            plot = "<c:lineChart><c:grouping val=\"standard\"/>\(series)<c:marker val=\"1\"/><c:smooth val=\"0\"/><c:axId val=\"10\"/><c:axId val=\"20\"/></c:lineChart>"
        } else {
            plot = "<c:barChart><c:barDir val=\"col\"/><c:grouping val=\"clustered\"/><c:varyColors val=\"0\"/>\(series)<c:gapWidth val=\"150\"/><c:overlap val=\"0\"/><c:axId val=\"10\"/><c:axId val=\"20\"/></c:barChart>"
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><c:chartSpace xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><c:chart>\(title)<c:plotArea><c:layout/>\(plot)<c:catAx><c:axId val=\"10\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"b\"/><c:tickLblPos val=\"nextTo\"/><c:crossAx val=\"20\"/><c:crosses val=\"autoZero\"/><c:auto val=\"1\"/><c:lblAlgn val=\"ctr\"/><c:lblOffset val=\"100\"/></c:catAx><c:valAx><c:axId val=\"20\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"l\"/><c:majorGridlines/><c:numFmt formatCode=\"General\" sourceLinked=\"1\"/><c:tickLblPos val=\"nextTo\"/><c:crossAx val=\"10\"/><c:crosses val=\"autoZero\"/></c:valAx></c:plotArea><c:plotVisOnly val=\"1\"/><c:dispBlanksAs val=\"gap\"/></c:chart><c:printSettings><c:headerFooter/><c:pageMargins b=\"0.75\" l=\"0.7\" r=\"0.7\" t=\"0.75\" header=\"0.3\" footer=\"0.3\"/><c:pageSetup/></c:printSettings></c:chartSpace>"
    }

    private static func columnLetters(_ column: Int) -> String {
        var value = max(0, column) + 1
        var name = ""
        while value > 0 {
            let remainder = (value - 1) % 26
            name = String(UnicodeScalar(65 + remainder)!) + name
            value = (value - 1) / 26
        }
        return name
    }

    private static func cellReference(row: Int, column: Int) -> String {
        var value = column + 1
        var name = ""
        while value > 0 {
            let remainder = (value - 1) % 26
            name = String(UnicodeScalar(65 + remainder)!) + name
            value = (value - 1) / 26
        }
        return "\(name)\(row + 1)"
    }

    private static func numberXML(_ source: String, value: Double) -> String {
        source.contains(",") ? String(value) : source
    }

    private static func styleIndex(_ style: GridCellStyle) -> Int {
        let fontIndex = (style.bold ? 1 : 0) + (style.italic ? 2 : 0)
        let fillIndex: Int
        switch style.fill {
        case "yellow": fillIndex = 2
        case "blue": fillIndex = 3
        case "green": fillIndex = 4
        case "red": fillIndex = 5
        default: fillIndex = 0
        }
        let numberFormatIndex: Int
        switch style.numberFormat {
        case "number": numberFormatIndex = 1
        case "currency": numberFormatIndex = 2
        case "percentage": numberFormatIndex = 3
        default: numberFormatIndex = 0
        }
        let borderIndex = style.border == "all" ? 1 : (style.border == "bottom" ? 2 : 0)
        return ((numberFormatIndex * 6 + fillIndex) * 4 + fontIndex) * 3 + borderIndex
    }

    private static func safeSheetName(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "[]:*?/\\")
        let cleaned = title.components(separatedBy: invalid).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty ? "Sheet1" : cleaned).prefix(31))
    }

    private static func normalizedWorksheetPath(_ target: String) -> String {
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        if target.hasPrefix("xl/") { return target }
        return "xl/" + target
    }

    private static func escapeXML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func parseSharedStrings(_ data: Data) -> [String] {
        let parser = SharedStringsXMLParser(data: data)
        guard parser.parse() else { return [] }
        return parser.strings
    }

    private static func parseStyles(_ data: Data) -> [Int: GridCellStyle] {
        let parser = StylesXMLParser(data: data)
        guard parser.parse() else { return [:] }
        var styles: [Int: GridCellStyle] = [:]
        for (index, format) in parser.formats.enumerated() {
            let bold = parser.fonts.indices.contains(format.font) ? parser.fonts[format.font].bold : false
            let italic = parser.fonts.indices.contains(format.font) ? parser.fonts[format.font].italic : false
            let color = parser.fills.indices.contains(format.fill) ? parser.fills[format.fill] : nil
            let colorHex = color.map { String($0.suffix(6)).uppercased() }
            let fill: String?
            if colorHex == "FFFF00" { fill = "yellow" }
            else if colorHex == "B8DFFF" { fill = "blue" }
            else if colorHex == "BAE8BE" { fill = "green" }
            else if colorHex == "FFC1BD" { fill = "red" }
            else { fill = nil }
            let numberFormat: String?
            switch format.numberFormatID {
            case 164: numberFormat = "number"
            case 165: numberFormat = "currency"
            case 166: numberFormat = "percentage"
            default: numberFormat = nil
            }
            let border = parser.borders.indices.contains(format.border) ? parser.borders[format.border] : nil
            styles[index] = GridCellStyle(bold: bold, italic: italic, fill: fill, numberFormat: numberFormat, border: border)
        }
        return styles
    }

    fileprivate static func value(_ values: [String: String], key: String) -> String? {
        values.first(where: { $0.key == key || $0.key.hasSuffix(":" + key) })?.value
    }

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>
    """
    private static let rootRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
    """
    private static let workbookRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
    """
    private static let stylesXML: String = {
        let fonts = (0..<4).map { index -> String in
            let bold = index == 1 || index == 3 ? "<b/>" : ""
            let italic = index == 2 || index == 3 ? "<i/>" : ""
            return "<font>\(bold)\(italic)<sz val=\"11\"/><name val=\"Aptos\"/><family val=\"2\"/></font>"
        }.joined()
        let fills = ["<fill><patternFill patternType=\"none\"/></fill>", "<fill><patternFill patternType=\"gray125\"/></fill>", "FFFFFF00", "FFB8DFFF", "FFBAE8BE", "FFFFC1BD"].enumerated().map { index, value in
            index < 2 ? value : "<fill><patternFill patternType=\"solid\"><fgColor rgb=\"\(value)\"/><bgColor indexed=\"64\"/></patternFill></fill>"
        }.joined()
        let borders = [
            "<border><left/><right/><top/><bottom/><diagonal/></border>",
            "<border><left style=\"thin\"><color auto=\"1\"/></left><right style=\"thin\"><color auto=\"1\"/></right><top style=\"thin\"><color auto=\"1\"/></top><bottom style=\"thin\"><color auto=\"1\"/></bottom><diagonal/></border>",
            "<border><left/><right/><top/><bottom style=\"thin\"><color auto=\"1\"/></bottom><diagonal/></border>"
        ]
        let cellFormats = (0..<4).flatMap { numberFormat in (0..<6).flatMap { fill in (0..<4).flatMap { font in (0..<3).map { border in
            let numberFormatID = [0, 164, 165, 166][numberFormat]
            return "<xf numFmtId=\"\(numberFormatID)\" fontId=\"\(font)\" fillId=\"\(fill)\" borderId=\"\(border)\" xfId=\"0\" applyFont=\"1\" applyFill=\"\(fill == 0 ? 0 : 1)\" applyNumberFormat=\"\(numberFormat == 0 ? 0 : 1)\" applyBorder=\"\(border == 0 ? 0 : 1)\"/>"
        }}}}}.joined()
        let currencySymbol = escapeXML(Locale.current.currencySymbol ?? "$")
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="3"><numFmt numFmtId="164" formatCode="#,##0.##"/><numFmt numFmtId="165" formatCode="&quot;\(currencySymbol)&quot;#,##0.##"/><numFmt numFmtId="166" formatCode="0.##%"/></numFmts><fonts count="4">\(fonts)</fonts><fills count="6">\(fills)</fills><borders count="3">\(borders.joined())</borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="288">\(cellFormats)</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
        """
    }()
    private static func workbookXML(sheets: [GridXlsxSheet]) -> String {
        let sheetXML = sheets.enumerated().map { index, sheet in "<sheet name=\"\(escapeXML(safeSheetName(sheet.sheetName)))\" sheetId=\"\(index + 1)\" r:id=\"rId\(index + 1)\"/>" }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><bookViews><workbookView/></bookViews><sheets>\(sheetXML)</sheets><calcPr calcId="191029" fullCalcOnLoad="1" forceFullCalc="1"/></workbook>
        """
    }

    private static func workbookRelationships(sheetCount: Int) -> String {
        let sheets = (0..<sheetCount).map { "<Relationship Id=\"rId\($0 + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0 + 1).xml\"/>" }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(sheets)<Relationship Id="rId\(sheetCount + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
        """
    }
}

private struct CellAddress: Hashable {
    let row: Int
    let column: Int
}

private final class WorkbookXMLParser: NSObject, XMLParserDelegate {
    let parser: XMLParser
    var sheets: [(name: String, relationshipID: String)] = []

    init(data: Data) { parser = XMLParser(data: data) }
    func parse() -> Bool { parser.delegate = self; return parser.parse() }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        guard name == "sheet",
              let sheetName = attributeDict["name"],
              let id = GridXlsxCodec.value(attributeDict, key: "id") else { return }
        sheets.append((sheetName, id))
    }
}

private final class RelationshipXMLParser: NSObject, XMLParserDelegate {
    let parser: XMLParser
    var targets: [String: String] = [:]

    init(data: Data) { parser = XMLParser(data: data) }
    func parse() -> Bool { parser.delegate = self; return parser.parse() }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        guard name == "Relationship",
              let id = attributeDict["Id"], let target = attributeDict["Target"] else { return }
        targets[id] = target
    }
}

private final class SharedStringsXMLParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var isInString = false
    private var isInText = false
    private var current = ""
    var strings: [String] = []

    init(data: Data) { parser = XMLParser(data: data) }
    func parse() -> Bool { parser.delegate = self; return parser.parse() }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName.split(separator: ":").last.map(String.init) ?? elementName {
        case "si": isInString = true; current = ""
        case "t": if isInString { isInText = true }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName.split(separator: ":").last.map(String.init) ?? elementName {
        case "t": isInText = false
        case "si": strings.append(current); isInString = false
        default: break
        }
    }
}

private final class WorksheetXMLParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private let sharedStrings: [String]
    private let styleMap: [Int: GridCellStyle]
    private var reference: CellAddress?
    private var cellType = ""
    private var formula: String?
    private var value = ""
    private var capture: String?
    private var styleIndex: Int?
    var values: [CellAddress: String] = [:]
    var cellStyles: [CellAddress: GridCellStyle] = [:]
    var drawingRelationshipID: String?

    init(data: Data, sharedStrings: [String], styleMap: [Int: GridCellStyle]) {
        parser = XMLParser(data: data)
        self.sharedStrings = sharedStrings
        self.styleMap = styleMap
    }

    func parse() -> Bool { parser.delegate = self; return parser.parse() }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName.split(separator: ":").last.map(String.init) ?? elementName {
        case "drawing": drawingRelationshipID = GridXlsxCodec.value(attributeDict, key: "id")
        case "c":
            reference = GridXlsxCodec.parseCellAddress(attributeDict["r"] ?? "")
            cellType = attributeDict["t"] ?? ""
            styleIndex = Int(attributeDict["s"] ?? "")
            formula = nil
            value = ""
        case "f": capture = "formula"
        case "v": capture = "value"
        case "t": if cellType == "inlineStr" { capture = "inline" }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        switch capture {
        case "formula": formula = (formula ?? "") + string
        case "value": value += string
        case "inline": value += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName.split(separator: ":").last.map(String.init) ?? elementName {
        case "f", "v", "t": capture = nil
        case "c":
            if let reference {
                if let formula { values[reference] = "=" + formula }
                else if cellType == "s", let index = Int(value), sharedStrings.indices.contains(index) { values[reference] = sharedStrings[index] }
                else { values[reference] = value }
                if let styleIndex, let style = styleMap[styleIndex] { cellStyles[reference] = style }
            }
            reference = nil
            styleIndex = nil
        default: break
        }
    }
}

private final class DrawingXMLParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    var chartRelationshipIDs: [String] = []

    init(data: Data) { parser = XMLParser(data: data) }
    func parse() -> Bool { parser.delegate = self; return parser.parse() }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if name == "chart", let id = GridXlsxCodec.value(attributeDict, key: "id") { chartRelationshipIDs.append(id) }
    }
}

private final class ChartXMLParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var inFormula = false
    private var inTitleText = false
    private var formula = ""
    private var titleDepth: Int?
    private var depth = 0
    private var isBarChart = false
    var formulas: [String] = []
    var title = ""
    var kind = "column"
    var seriesCount = 0
    var chartTypeSupported = false

    init(data: Data) { parser = XMLParser(data: data) }
    func parse() -> Bool { parser.delegate = self; return parser.parse() }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        depth += 1
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        switch name {
        case "lineChart": kind = "line"; chartTypeSupported = true
        case "barChart": isBarChart = true
        case "barDir" where isBarChart: kind = "column"; chartTypeSupported = attributeDict["val"] == "col"
        case "ser": seriesCount += 1
        case "title" where titleDepth == nil: titleDepth = depth
        case "f": inFormula = true; formula = ""
        case "t": if titleDepth != nil { inTitleText = true }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inFormula { formula += string }
        if inTitleText { title += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if name == "f" { formulas.append(formula); inFormula = false }
        if name == "t" { inTitleText = false }
        if name == "title", titleDepth == depth { titleDepth = nil }
        depth -= 1
    }
}

private final class StylesXMLParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var inFont = false
    private var inFill = false
    private var inCellFormats = false
    private var bold = false
    private var italic = false
    private var fillColor: String?
    var fonts: [(bold: Bool, italic: Bool)] = []
    var fills: [String?] = []
    var formats: [(font: Int, fill: Int, border: Int, numberFormatID: Int)] = []
    var borders: [String?] = []
    private var inBorders = false
    private var inBorder = false
    private var borderSides = Set<String>()

    init(data: Data) { parser = XMLParser(data: data) }
    func parse() -> Bool { parser.delegate = self; return parser.parse() }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        switch name {
        case "font": inFont = true; bold = false; italic = false
        case "fill": inFill = true; fillColor = nil
        case "cellXfs": inCellFormats = true
        case "borders": inBorders = true
        case "border" where inBorders: inBorder = true; borderSides = []
        case "b": if inFont { bold = attributeDict["val"] != "0" && attributeDict["val"] != "false" }
        case "i": if inFont { italic = attributeDict["val"] != "0" && attributeDict["val"] != "false" }
        case "fgColor": if inFill { fillColor = attributeDict["rgb"] }
        case "left", "right", "top", "bottom":
            if inBorder, attributeDict["style"] != nil { borderSides.insert(name) }
        case "xf" where inCellFormats:
            formats.append((Int(attributeDict["fontId"] ?? "0") ?? 0, Int(attributeDict["fillId"] ?? "0") ?? 0, Int(attributeDict["borderId"] ?? "0") ?? 0, Int(attributeDict["numFmtId"] ?? "0") ?? 0))
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        switch name {
        case "font": fonts.append((bold, italic)); inFont = false
        case "fill": fills.append(fillColor); inFill = false
        case "cellXfs": inCellFormats = false
        case "border":
            let sides: Set<String> = ["left", "right", "top", "bottom"]
            borders.append(borderSides.isSuperset(of: sides) ? "all" : (borderSides.contains("bottom") ? "bottom" : nil))
            inBorder = false
        case "borders": inBorders = false
        default: break
        }
    }
}

extension GridXlsxCodec {
    fileprivate static func parseCellAddress(_ address: String) -> CellAddress? {
        let letters = String(address.prefix { $0.isLetter }).uppercased()
        guard !letters.isEmpty, let rowNumber = Int(address.dropFirst(letters.count)), rowNumber > 0 else { return nil }
        let columnNumber = letters.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 }
        guard columnNumber > 0 else { return nil }
        return CellAddress(row: rowNumber - 1, column: columnNumber - 1)
    }
}
