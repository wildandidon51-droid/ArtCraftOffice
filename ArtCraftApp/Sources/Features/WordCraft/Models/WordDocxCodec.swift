import Foundation
import UIKit

enum WordDocxCodecError: Error {
    case missingDocument
    case invalidArchive
    case documentTooLarge
}

struct WordDocxContent {
    let attributedText: NSAttributedString
    let paperSize: WordPaperSize
    let pageOrientation: WordPageOrientation
    let marginPreset: WordMarginPreset
}

enum WordDocxCodec {
    private static let maximumDocumentXMLSize: UInt64 = 32_000_000
    private static let maximumArchiveSize = 100_000_000

    static func encode(
        _ text: NSAttributedString,
        paperSize: WordPaperSize = .a4,
        pageOrientation: WordPageOrientation = .portrait,
        marginPreset: WordMarginPreset = .normal
    ) throws -> Data {
        try OfficeOpenXMLArchive.create(entries: [
            "[Content_Types].xml": Data(contentTypes.utf8),
            "_rels/.rels": Data(rootRelationships.utf8),
            "word/document.xml": Data(documentXML(for: text, paperSize: paperSize, pageOrientation: pageOrientation, marginPreset: marginPreset).utf8),
            "word/styles.xml": Data(stylesXML.utf8)
        ])
    }

    static func decode(_ data: Data) throws -> NSAttributedString {
        try decodeDocument(data).attributedText
    }

    static func decodeDocument(_ data: Data) throws -> WordDocxContent {
        guard data.count <= maximumArchiveSize else { throw WordDocxCodecError.documentTooLarge }
        let xml = try OfficeOpenXMLArchive.read("word/document.xml", from: data, maximumSize: maximumDocumentXMLSize)
        let parser = XMLParser(data: xml)
        let delegate = WordDocumentXMLParser()
        parser.delegate = delegate
        guard parser.parse() else { throw WordDocxCodecError.invalidArchive }
        let geometry = delegate.pageGeometry
        let landscape = geometry.orientation == "landscape" || (geometry.width ?? 0) > (geometry.height ?? 0)
        let portraitWidth = landscape ? (geometry.height ?? Double(WordPaperSize.a4.dimensions.height)) : (geometry.width ?? Double(WordPaperSize.a4.dimensions.width))
        let portraitHeight = landscape ? (geometry.width ?? Double(WordPaperSize.a4.dimensions.height)) : (geometry.height ?? Double(WordPaperSize.a4.dimensions.height))
        let paperSize = WordPaperSize.allCases.min { lhs, rhs in
            let left = abs(Double(lhs.dimensions.width) - portraitWidth) + abs(Double(lhs.dimensions.height) - portraitHeight)
            let right = abs(Double(rhs.dimensions.width) - portraitWidth) + abs(Double(rhs.dimensions.height) - portraitHeight)
            return left < right
        } ?? .a4
        let marginPoints = geometry.margins.isEmpty ? Double(WordMarginPreset.normal.value) : geometry.margins.reduce(0, +) / Double(geometry.margins.count)
        let marginPreset = WordMarginPreset.allCases.min { abs(Double($0.value) - marginPoints) < abs(Double($1.value) - marginPoints) } ?? .normal
        return WordDocxContent(attributedText: delegate.output, paperSize: paperSize,
                               pageOrientation: landscape ? .landscape : .portrait, marginPreset: marginPreset)
    }

    private static func documentXML(for text: NSAttributedString, paperSize: WordPaperSize, pageOrientation: WordPageOrientation, marginPreset: WordMarginPreset) -> String {
        let content = text.string as NSString
        var paragraphs: [String] = []
        var start = 0
        while start <= content.length {
            let searchRange = NSRange(location: start, length: content.length - start)
            let newline = content.range(of: "\n", options: [], range: searchRange)
            let end = newline.location == NSNotFound ? content.length : newline.location
            paragraphs.append(paragraphXML(text, range: NSRange(location: start, length: end - start)))
            if newline.location == NSNotFound { break }
            start = newline.location + newline.length
        }
        if paragraphs.isEmpty { paragraphs = ["<w:p/>"] }
        let points = paperSize.dimensions
        let widthPoints = pageOrientation == .landscape ? points.height : points.width
        let heightPoints = pageOrientation == .landscape ? points.width : points.height
        let widthTwips = Int((widthPoints * 20).rounded())
        let heightTwips = Int((heightPoints * 20).rounded())
        let marginTwips = Int((marginPreset.value * 20).rounded())
        let orientation = pageOrientation == .landscape ? " w:orient=\"landscape\"" : ""
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>\(paragraphs.joined())<w:sectPr><w:pgSz w:w="\(widthTwips)" w:h="\(heightTwips)"\(orientation)/><w:pgMar w:top="\(marginTwips)" w:right="\(marginTwips)" w:bottom="\(marginTwips)" w:left="\(marginTwips)" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>
        """
    }

    private static func paragraphXML(_ text: NSAttributedString, range: NSRange) -> String {
        guard range.length > 0 else { return "<w:p/>" }
        let paragraphAttributes = text.attributes(at: range.location, effectiveRange: nil)
        let paragraphStyle = paragraphAttributes[.paragraphStyle] as? NSParagraphStyle
        let justification: String
        switch paragraphStyle?.alignment ?? .left {
        case .center: justification = "center"
        case .right: justification = "right"
        case .justified: justification = "both"
        default: justification = "left"
        }
        let paragraphProperties = justification == "left" ? "" : "<w:pPr><w:jc w:val=\"\(justification)\"/></w:pPr>"
        var runs = ""
        text.enumerateAttributes(in: range) { attributes, subrange, _ in
            let value = (text.string as NSString).substring(with: subrange)
            guard !value.isEmpty else { return }
            let font = attributes[.font] as? UIFont ?? .systemFont(ofSize: 12)
            let traits = font.fontDescriptor.symbolicTraits
            let bold = traits.contains(.traitBold) ? "<w:b/>" : ""
            let italic = traits.contains(.traitItalic) ? "<w:i/>" : ""
            let underline = (attributes[.underlineStyle] as? NSNumber)?.intValue ?? 0
            let underlineXML = underline == 0 ? "" : "<w:u w:val=\"single\"/>"
            let color = (attributes[.foregroundColor] as? UIColor).flatMap(hexColor) ?? "000000"
            let family = escapeXML(font.familyName)
            let size = max(2, Int((font.pointSize * 2).rounded()))
            let runProperties = "<w:rPr><w:rFonts w:ascii=\"\(family)\" w:hAnsi=\"\(family)\"/>\(bold)\(italic)\(underlineXML)<w:color w:val=\"\(color)\"/><w:sz w:val=\"\(size)\"/></w:rPr>"
            let pieces = value.components(separatedBy: "\u{000C}")
            for (pieceIndex, piece) in pieces.enumerated() {
                if !piece.isEmpty { runs += "<w:r>\(runProperties)<w:t xml:space=\"preserve\">\(escapeXML(piece))</w:t></w:r>" }
                if pieceIndex < pieces.count - 1 { runs += "<w:r>\(runProperties)<w:br w:type=\"page\"/></w:r>" }
            }
        }
        return "<w:p>\(paragraphProperties)\(runs)</w:p>"
    }

    private static func hexColor(_ color: UIColor) -> String? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: nil) else { return nil }
        return String(format: "%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }

    private static func escapeXML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>
    """

    private static let rootRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
    """

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="24"/></w:rPr></w:rPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>
    """
}

private final class WordDocumentXMLParser: NSObject, XMLParserDelegate {
    let output = NSMutableAttributedString(string: "")
    private var attributes: [NSAttributedString.Key: Any] = [:]
    private var isBold = false
    private var isItalic = false
    private var fontSize: CGFloat = 12
    private var fontFamily = "Arial"
    private var paragraphAlignment: NSTextAlignment = .left
    private var pageWidthTwips: Double?
    private var pageHeightTwips: Double?
    private var pageOrientationValue: String?
    private var pageMarginsTwips: [Double] = []

    var pageGeometry: (width: Double?, height: Double?, orientation: String?, margins: [Double]) {
        (pageWidthTwips.map { $0 / 20 }, pageHeightTwips.map { $0 / 20 }, pageOrientationValue,
         pageMarginsTwips.map { $0 / 20 })
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        switch name {
        case "pgSz":
            pageWidthTwips = attributeValue(attributeDict, key: "w").flatMap { Double($0) }
            pageHeightTwips = attributeValue(attributeDict, key: "h").flatMap { Double($0) }
            pageOrientationValue = attributeValue(attributeDict, key: "orient")
        case "pgMar":
            let marginKeys = ["top", "right", "bottom", "left"]
            pageMarginsTwips = marginKeys.compactMap { key in attributeValue(attributeDict, key: key).flatMap { Double($0) } }
        case "p":
            if output.length > 0 { output.append(NSAttributedString(string: "\n")) }
            paragraphAlignment = .left
        case "r":
            isBold = false
            isItalic = false
            fontSize = 12
            fontFamily = "Arial"
            attributes = [:]
        case "b": isBold = attributeValue(attributeDict, key: "val") != "0" && attributeValue(attributeDict, key: "val") != "false"
        case "i": isItalic = attributeValue(attributeDict, key: "val") != "0" && attributeValue(attributeDict, key: "val") != "false"
        case "u": attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        case "sz": if let halfPoints = Double(attributeValue(attributeDict, key: "val") ?? ""), halfPoints > 0 { fontSize = CGFloat(halfPoints / 2) }
        case "rFonts": fontFamily = attributeValue(attributeDict, key: "ascii") ?? fontFamily
        case "color":
            if let hex = attributeValue(attributeDict, key: "val"), hex.count == 6, let number = UInt32(hex, radix: 16) {
                attributes[.foregroundColor] = UIColor(red: CGFloat((number >> 16) & 0xFF) / 255, green: CGFloat((number >> 8) & 0xFF) / 255, blue: CGFloat(number & 0xFF) / 255, alpha: 1)
            }
        case "jc":
            switch attributeValue(attributeDict, key: "val") {
            case "center": paragraphAlignment = .center
            case "right", "end": paragraphAlignment = .right
            case "both", "distribute": paragraphAlignment = .justified
            default: paragraphAlignment = .left
            }
        case "tab": appendText("\t")
        case "br": appendText(attributeValue(attributeDict, key: "type") == "page" ? "\u{000C}" : "\n")
        case "cr": appendText("\n")
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        appendText(string)
    }

    private func appendText(_ string: String) {
        guard !string.isEmpty else { return }
        var traits: UIFontDescriptor.SymbolicTraits = []
        if isBold { traits.insert(.traitBold) }
        if isItalic { traits.insert(.traitItalic) }
        let base = UIFont(name: fontFamily, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let font = UIFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor, size: fontSize)
        var runAttributes = attributes
        runAttributes[.font] = font
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = paragraphAlignment
        runAttributes[.paragraphStyle] = paragraphStyle
        output.append(NSAttributedString(string: string, attributes: runAttributes))
    }

    private func attributeValue(_ values: [String: String], key: String) -> String? {
        values.first(where: { $0.key == key || $0.key.hasSuffix(":" + key) })?.value
    }
}
