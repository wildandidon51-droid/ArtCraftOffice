import Foundation

struct DeckPptxSlide {
    var title: String
    var body: String
    var notes: String = ""
    var imageData: Data? = nil
    var additionalImageData: [Data] = []
    var images: [Data] { (imageData.map { [$0] } ?? []) + additionalImageData }

    init(title: String, body: String, notes: String = "", imageData: Data? = nil, images: [Data]? = nil) {
        self.title = title
        self.body = body
        self.notes = notes
        let values = images ?? (imageData.map { [$0] } ?? [])
        self.imageData = values.first
        additionalImageData = Array(values.dropFirst())
    }
}

struct DeckPptxContent {
    var slides: [DeckPptxSlide]
    var theme: String
    var title: String?
}

enum DeckPptxCodecError: Error {
    case invalidPresentation
    case noSlides
    case presentationTooLarge
}

enum DeckPptxCodec {
    private static let maxArchiveSize = 100_000_000
    private static let maxPartSize: UInt64 = 32_000_000
    private static let maxSlides = 500

    static func encode(title: String, slides: [DeckPptxSlide], theme: String) throws -> Data {
        guard !slides.isEmpty else { throw DeckPptxCodecError.noSlides }
        guard slides.count <= maxSlides else { throw DeckPptxCodecError.presentationTooLarge }
        let colors = ThemeColors(theme: theme)
        var entries: [String: Data] = [
            "[Content_Types].xml": Data(contentTypes(slideCount: slides.count).utf8),
            "_rels/.rels": Data(rootRelationships.utf8),
            "docProps/core.xml": Data(coreProperties(title: title).utf8),
            "docProps/app.xml": Data(appProperties.utf8),
            "ppt/presentation.xml": Data(presentationXML(slides: slides).utf8),
            "ppt/_rels/presentation.xml.rels": Data(presentationRelationships(slideCount: slides.count).utf8),
            "ppt/presProps.xml": Data(presentationProperties.utf8),
            "ppt/viewProps.xml": Data(viewProperties.utf8),
            "ppt/tableStyles.xml": Data(tableStyles.utf8),
            "ppt/slideMasters/slideMaster1.xml": Data(slideMaster.utf8),
            "ppt/slideMasters/_rels/slideMaster1.xml.rels": Data(masterRelationships.utf8),
            "ppt/slideLayouts/slideLayout1.xml": Data(slideLayout.utf8),
            "ppt/slideLayouts/_rels/slideLayout1.xml.rels": Data(layoutRelationships.utf8),
            "ppt/notesMasters/notesMaster1.xml": Data(notesMasterXML.utf8),
            "ppt/notesMasters/_rels/notesMaster1.xml.rels": Data(notesMasterRelationships.utf8),
            "ppt/theme/theme1.xml": Data(themeXML(colors: colors).utf8)
        ]
        for (index, slide) in slides.enumerated() {
            let number = index + 1
            entries["ppt/slides/slide\(number).xml"] = Data(slideXML(slide, colors: colors).utf8)
            let relationships = slideRelationships(imageCount: slide.images.count, slideNumber: number)
            entries["ppt/slides/_rels/slide\(number).xml.rels"] = Data(relationships.utf8)
            entries["ppt/notesSlides/notesSlide\(number).xml"] = Data(notesSlideXML(slide.notes).utf8)
            entries["ppt/notesSlides/_rels/notesSlide\(number).xml.rels"] = Data(notesSlideRelationships(slideNumber: number).utf8)
            for (imageIndex, imageData) in slide.images.enumerated() {
                entries["ppt/media/image\(number)_\(imageIndex + 1).jpg"] = imageData
            }
        }
        return try OfficeOpenXMLArchive.create(entries: entries)
    }

    static func decode(_ data: Data) throws -> DeckPptxContent {
        guard data.count <= maxArchiveSize else { throw DeckPptxCodecError.presentationTooLarge }
        let presentationData = try OfficeOpenXMLArchive.read("ppt/presentation.xml", from: data, maximumSize: maxPartSize)
        let relationshipsData = try OfficeOpenXMLArchive.read("ppt/_rels/presentation.xml.rels", from: data, maximumSize: maxPartSize)
        let presentation = PPTXPresentationParser(data: presentationData)
        guard presentation.parse(), !presentation.slideRelationshipIDs.isEmpty,
              presentation.slideRelationshipIDs.count <= maxSlides else { throw DeckPptxCodecError.invalidPresentation }
        let relationships = PPTXRelationshipsParser(data: relationshipsData)
        guard relationships.parse() else { throw DeckPptxCodecError.invalidPresentation }

        var slides: [DeckPptxSlide] = []
        var detectedTheme: String?
        for relationshipID in presentation.slideRelationshipIDs {
            guard let target = relationships.targets[relationshipID] else { throw DeckPptxCodecError.invalidPresentation }
            let path = normalizeSlidePath(target)
            guard path.hasPrefix("ppt/slides/"), path.hasSuffix(".xml") else { throw DeckPptxCodecError.invalidPresentation }
            let xml = try OfficeOpenXMLArchive.read(path, from: data, maximumSize: maxPartSize)
            let parser = PPTXSlideParser(data: xml)
            guard parser.parse() else { throw DeckPptxCodecError.invalidPresentation }
            let relationshipsPath = slideRelationshipsPath(for: path)
            let relationshipsXML = try? OfficeOpenXMLArchive.read(relationshipsPath, from: data, maximumSize: maxPartSize)
            let slideRelationships = relationshipsXML.map(PPTXRelationshipsParser.init(data:))
            let relationshipsParsed = slideRelationships?.parse() == true
            var images: [Data] = []
            if relationshipsParsed {
                for relationshipID in parser.imageRelationshipIDs {
                    guard let imageTarget = slideRelationships?.targets[relationshipID],
                          let imagePath = normalizeRelationshipPath(imageTarget, relativeTo: path),
                          let imageData = try? OfficeOpenXMLArchive.read(imagePath, from: data, maximumSize: maxPartSize) else { continue }
                    images.append(imageData)
                }
            }
            var notes = ""
            if relationshipsParsed, let notesRelationshipID = slideRelationships?.types.first(where: { $0.value.hasSuffix("/notesSlide") })?.key,
               let notesTarget = slideRelationships?.targets[notesRelationshipID],
               let notesPath = normalizePartPath(notesTarget, relativeTo: path, requiredPrefix: "ppt/notesSlides/"),
               let notesXML = try? OfficeOpenXMLArchive.read(notesPath, from: data, maximumSize: maxPartSize) {
                let notesParser = PPTXSlideParser(data: notesXML)
                if notesParser.parse() {
                    notes = notesParser.shapes.first(where: { $0.placeholderType == "body" })?.text ?? ""
                }
            }
            let nonemptyShapes = parser.shapes.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let titleShape = nonemptyShapes.first(where: { $0.isTitle }) ?? nonemptyShapes.first
            let title = titleShape?.text ?? "Untitled slide"
            let body = nonemptyShapes.filter { $0.id != titleShape?.id }.map(\.text).joined(separator: "\n")
            slides.append(DeckPptxSlide(title: title, body: body, notes: notes, images: images))
            if detectedTheme == nil, let background = parser.backgroundColor {
                detectedTheme = ThemeColors.name(for: background)
            }
        }
        guard !slides.isEmpty else { throw DeckPptxCodecError.noSlides }
        let titleData = try? OfficeOpenXMLArchive.read("docProps/core.xml", from: data, maximumSize: maxPartSize)
        let coreProperties = titleData.map(PPTXCorePropertiesParser.init(data:))
        let documentTitle = coreProperties.flatMap { $0.parse() ? $0.title : nil }
        return DeckPptxContent(slides: slides, theme: detectedTheme ?? "Midnight", title: documentTitle)
    }

    private static func normalizeSlidePath(_ target: String) -> String {
        let path = target.hasPrefix("/") ? String(target.dropFirst()) : "ppt/" + target
        var components: [String] = []
        for component in path.split(separator: "/") {
            if component == ".." { if !components.isEmpty { components.removeLast() } }
            else if component != "." { components.append(String(component)) }
        }
        return components.joined(separator: "/")
    }

    private static func slideRelationshipsPath(for slidePath: String) -> String {
        guard let slash = slidePath.lastIndex(of: "/") else { return "ppt/slides/_rels/slide.xml.rels" }
        let folder = slidePath[..<slash]
        let name = slidePath[slidePath.index(after: slash)...]
        return "\(folder)/_rels/\(name).rels"
    }

    private static func normalizeRelationshipPath(_ target: String, relativeTo sourcePart: String) -> String? {
        normalizePartPath(target, relativeTo: sourcePart, requiredPrefix: "ppt/media/")
    }

    private static func normalizePartPath(_ target: String, relativeTo sourcePart: String, requiredPrefix: String) -> String? {
        var components = target.hasPrefix("/") ? [] : sourcePart.split(separator: "/").dropLast().map(String.init)
        for component in target.split(separator: "/") {
            if component == ".." {
                guard !components.isEmpty else { return nil }
                components.removeLast()
            } else if component != "." {
                components.append(String(component))
            }
        }
        let path = components.joined(separator: "/")
        return path.hasPrefix(requiredPrefix) ? path : nil
    }

    private static func notesSlideXML(_ notes: String) -> String {
        let paragraphs = notes.components(separatedBy: "\n").map { line in
            "<a:p><a:r><a:rPr lang=\"en-US\"/><a:t xml:space=\"preserve\">\(escapeXML(line))</a:t></a:r><a:endParaRPr lang=\"en-US\"/></a:p>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:notes xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr><p:sp><p:nvSpPr><p:cNvPr id="2" name="Notes Placeholder"/><p:cNvSpPr txBox="1"/><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x="914400" y="1143000"/><a:ext cx="5486400" cy="6858000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr><p:txBody><a:bodyPr wrap="square" anchor="t"/><a:lstStyle/>\(paragraphs)</p:txBody></p:sp></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>
        """
    }

    private static func notesSlideRelationships(slideNumber: Int) -> String {
        xmlRelationships("<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"../slides/slide\(slideNumber).xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster\" Target=\"../notesMasters/notesMaster1.xml\"/>")
    }

    private static func slideXML(_ slide: DeckPptxSlide, colors: ThemeColors) -> String {
        let bodyWidth = slide.images.isEmpty ? 10058400 : 5500000
        let pictures = slide.images.indices.map { pictureShape(index: $0, imageCount: slide.images.count) }.joined()
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld name="Slide"><p:bg><p:bgPr><a:solidFill><a:srgbClr val="\(colors.background)"/></a:solidFill><a:effectLst/></p:bgPr></p:bg><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>\(textShape(id: 2, name: "Title", placeholder: "title", text: slide.title, color: colors.foreground, fontSize: 4400, bold: true, x: 914400, y: 457200, width: 10363200, height: 1250000))\(textShape(id: 3, name: "Body", placeholder: "body", text: slide.body, color: colors.foreground, fontSize: 2600, bold: false, x: 1040000, y: 2200000, width: bodyWidth, height: 4200000))\(pictures)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>
        """
    }

    private static func pictureShape(index: Int, imageCount: Int) -> String {
        let column = index % 2
        let row = index / 2
        let x = imageCount == 1 ? 6400000 : 6400000 + column * 2400000
        let rowCount = max(1, (imageCount + 1) / 2)
        let rowHeight = 4200000 / rowCount
        let y = 2200000 + row * rowHeight
        let width = imageCount == 1 ? 4800000 : 2200000
        let height = imageCount == 1 ? 4200000 : min(1900000, rowHeight * 9 / 10)
        return "<p:pic><p:nvPicPr><p:cNvPr id=\"\(index + 4)\" name=\"Slide picture \(index + 1)\"/><p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"rId\(index + 2)\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x=\"\(x)\" y=\"\(y)\"/><a:ext cx=\"\(width)\" cy=\"\(height)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>"
    }

    private static func textShape(id: Int, name: String, placeholder: String, text: String, color: String, fontSize: Int, bold: Bool, x: Int, y: Int, width: Int, height: Int) -> String {
        let textParagraphs = text.components(separatedBy: "\n")
        let paragraphs = (textParagraphs.isEmpty ? [""] : textParagraphs).map { paragraph in
            "<a:p><a:pPr algn=\"l\"/><a:r><a:rPr lang=\"en-US\" sz=\"\(fontSize)\" b=\"\(bold ? 1 : 0)\"><a:solidFill><a:srgbClr val=\"\(color)\"/></a:solidFill><a:latin typeface=\"Aptos\"/></a:rPr><a:t xml:space=\"preserve\">\(escapeXML(paragraph))</a:t></a:r><a:endParaRPr lang=\"en-US\"/></a:p>"
        }.joined()
        return "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"\(name)\"/><p:cNvSpPr/><p:nvPr><p:ph type=\"\(placeholder)\"/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\(x)\" y=\"\(y)\"/><a:ext cx=\"\(width)\" cy=\"\(height)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/></p:spPr><p:txBody><a:bodyPr wrap=\"square\" anchor=\"t\"/><a:lstStyle/>\(paragraphs)</p:txBody></p:sp>"
    }

    private static func presentationXML(slides: [DeckPptxSlide]) -> String {
        let slideIDs = slides.enumerated().map { index, _ in "<p:sldId id=\"\(256 + index)\" r:id=\"rId\(index + 2)\"/>" }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst><p:notesMasterIdLst><p:notesMasterId r:id="rId\(slides.count + 5)"/></p:notesMasterIdLst><p:sldIdLst>\(slideIDs)</p:sldIdLst><p:sldSz cx="12192000" cy="6858000" type="screen16x9"/><p:notesSz cx="6858000" cy="9144000"/><p:defaultTextStyle><a:defPPr><a:defRPr lang="en-US"/></a:defPPr></p:defaultTextStyle></p:presentation>
        """
    }

    private static func presentationRelationships(slideCount: Int) -> String {
        var values = ["<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"slideMasters/slideMaster1.xml\"/>"]
        for index in 0..<slideCount {
            values.append("<Relationship Id=\"rId\(index + 2)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide\(index + 1).xml\"/>")
        }
        values.append("<Relationship Id=\"rId\(slideCount + 2)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/presProps\" Target=\"presProps.xml\"/>")
        values.append("<Relationship Id=\"rId\(slideCount + 3)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/viewProps\" Target=\"viewProps.xml\"/>")
        values.append("<Relationship Id=\"rId\(slideCount + 4)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/tableStyles\" Target=\"tableStyles.xml\"/>")
        values.append("<Relationship Id=\"rId\(slideCount + 5)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster\" Target=\"notesMasters/notesMaster1.xml\"/>")
        return xmlRelationships(values.joined())
    }

    private static func contentTypes(slideCount: Int) -> String {
        var overrides = "<Override PartName=\"/ppt/presentation.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml\"/><Override PartName=\"/ppt/presProps.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.presProps+xml\"/><Override PartName=\"/ppt/viewProps.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.viewProps+xml\"/><Override PartName=\"/ppt/tableStyles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.tableStyles+xml\"/><Override PartName=\"/ppt/slideMasters/slideMaster1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml\"/><Override PartName=\"/ppt/slideLayouts/slideLayout1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml\"/><Override PartName=\"/ppt/theme/theme1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.theme+xml\"/>"
        overrides += "<Override PartName=\"/ppt/notesMasters/notesMaster1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml\"/>"
        if slideCount > 0 {
            for index in 1...slideCount {
                overrides += "<Override PartName=\"/ppt/slides/slide\(index).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>"
                overrides += "<Override PartName=\"/ppt/notesSlides/notesSlide\(index).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml\"/>"
            }
        }
        overrides += "<Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/><Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/>"
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Default Extension=\"jpg\" ContentType=\"image/jpeg\"/>\(overrides)</Types>"
    }

    private static func xmlRelationships(_ items: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(items)</Relationships>"
    }

    private static func escapeXML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static let rootRelationships = xmlRelationships("<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"ppt/presentation.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/><Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties\" Target=\"docProps/app.xml\"/>")
    }
    private static func coreProperties(title: String) -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><dc:title>\(escapeXML(title))</dc:title><dc:creator>ArtCraft Office</dc:creator><cp:lastModifiedBy>ArtCraft Office</cp:lastModifiedBy><dcterms:created xsi:type=\"dcterms:W3CDTF\">\(timestamp)</dcterms:created><dcterms:modified xsi:type=\"dcterms:W3CDTF\">\(timestamp)</dcterms:modified></cp:coreProperties>"
    }
    private static let appProperties = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\" xmlns:vt=\"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes\"><Application>ArtCraft Office</Application><PresentationFormat>Widescreen</PresentationFormat></Properties>"
    private static let presentationProperties = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><p:presentationPr xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\"/>"
    private static let viewProperties = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><p:viewPr xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\"><p:normalViewPr/></p:viewPr>"
    private static let tableStyles = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><a:tblStyleLst xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" def=\"{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}\"/>"
    private static let notesMasterXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><p:notesMaster xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm/></p:grpSpPr></p:spTree></p:cSld><p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/><p:notesStyle><a:lvl1pPr><a:defRPr lang=\"en-US\"/></a:lvl1pPr></p:notesStyle></p:notesMaster>"
    private static let notesMasterRelationships = xmlRelationships("<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme\" Target=\"../theme/theme1.xml\"/>")
    private static let slideLayout = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><p:sldLayout xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" type=\"blank\" preserve=\"1\"><p:cSld name=\"Blank\"><p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm/></p:grpSpPr></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>"
    private static let slideMaster = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><p:sldMaster xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\"><p:cSld name=\"ArtCraft Master\"><p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm/></p:grpSpPr></p:spTree></p:cSld><p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/><p:sldLayoutIdLst><p:sldLayoutId id=\"2147483649\" r:id=\"rId1\"/></p:sldLayoutIdLst><p:txStyles><p:titleStyle><a:lvl1pPr><a:defRPr lang=\"en-US\"/></a:lvl1pPr></p:titleStyle><p:bodyStyle><a:lvl1pPr><a:defRPr lang=\"en-US\"/></a:lvl1pPr></p:bodyStyle><p:otherStyle><a:lvl1pPr><a:defRPr lang=\"en-US\"/></a:lvl1pPr></p:otherStyle></p:txStyles></p:sldMaster>"
    private static let masterRelationships = xmlRelationships("<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme\" Target=\"../theme/theme1.xml\"/>")
    private static let layoutRelationships = xmlRelationships("<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"../slideMasters/slideMaster1.xml\"/>")
    private static func slideRelationships(imageCount: Int, slideNumber: Int) -> String {
        var values = "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/>"
        for index in 0..<imageCount {
            values += "<Relationship Id=\"rId\(index + 2)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../media/image\(slideNumber)_\(index + 1).jpg\"/>"
        }
        values += "<Relationship Id=\"rId\(imageCount + 2)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide\" Target=\"../notesSlides/notesSlide\(slideNumber).xml\"/>"
        return xmlRelationships(values)
    }

    private static func themeXML(colors: ThemeColors) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><a:theme xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" name=\"ArtCraft\"><a:themeElements><a:clrScheme name=\"ArtCraft\"><a:dk1><a:srgbClr val=\"\(colors.foreground)\"/></a:dk1><a:lt1><a:srgbClr val=\"\(colors.background)\"/></a:lt1><a:dk2><a:srgbClr val=\"1F1F1F\"/></a:dk2><a:lt2><a:srgbClr val=\"FFFFFF\"/></a:lt2><a:accent1><a:srgbClr val=\"4472C4\"/></a:accent1><a:accent2><a:srgbClr val=\"ED7D31\"/></a:accent2><a:accent3><a:srgbClr val=\"A5A5A5\"/></a:accent3><a:accent4><a:srgbClr val=\"FFC000\"/></a:accent4><a:accent5><a:srgbClr val=\"5B9BD5\"/></a:accent5><a:accent6><a:srgbClr val=\"70AD47\"/></a:accent6><a:hlink><a:srgbClr val=\"0563C1\"/></a:hlink><a:folHlink><a:srgbClr val=\"954F72\"/></a:folHlink></a:clrScheme><a:fontScheme name=\"ArtCraft\"><a:majorFont><a:latin typeface=\"Aptos Display\"/><a:ea/><a:cs/></a:majorFont><a:minorFont><a:latin typeface=\"Aptos\"/><a:ea/><a:cs/></a:minorFont></a:fontScheme><a:fmtScheme name=\"ArtCraft\"><a:fillStyleLst><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln w=\"6350\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln><a:ln w=\"12700\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln><a:ln w=\"19050\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme></a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>"
    }
}

private struct ThemeColors {
    let background: String
    let foreground: String

    init(theme: String) {
        switch theme {
        case "Paper": background = "FAF7ED"; foreground = "222222"
        case "Ocean": background = "05526B"; foreground = "FFFFFF"
        default: background = "141C33"; foreground = "FFFFFF"
        }
    }

    static func name(for hex: String) -> String {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return "Midnight" }
        let red = (value >> 16) & 255
        let green = (value >> 8) & 255
        let blue = value & 255
        if red > 215 && green > 215 && blue > 215 { return "Paper" }
        if blue > red && green > red && blue > 80 { return "Ocean" }
        return "Midnight"
    }
}

private final class PPTXPresentationParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    var slideRelationshipIDs: [String] = []
    init(data: Data) { parser = XMLParser(data: data) }
    func parse() -> Bool { parser.delegate = self; return parser.parse() }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName.split(separator: ":").last == "sldId",
              let id = attributeDict.first(where: { $0.key == "id" || $0.key.hasSuffix(":id") })?.value else { return }
        slideRelationshipIDs.append(id)
    }
}

private final class PPTXRelationshipsParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    var targets: [String: String] = [:]
    var types: [String: String] = [:]
    init(data: Data) { parser = XMLParser(data: data) }
    func parse() -> Bool { parser.delegate = self; return parser.parse() }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName.split(separator: ":").last == "Relationship",
              let id = attributeDict["Id"], let target = attributeDict["Target"] else { return }
        targets[id] = target
        if let type = attributeDict["Type"] { types[id] = type }
    }
}

private final class PPTXCorePropertiesParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var readingTitle = false
    var title = ""
    init(data: Data) { parser = XMLParser(data: data) }
    func parse() -> Bool { parser.delegate = self; return parser.parse() }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        readingTitle = elementName.split(separator: ":").last == "title"
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if readingTitle { title += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName.split(separator: ":").last == "title" { readingTitle = false }
    }
}

private final class PPTXSlideParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var currentShape: PPTXShapeText?
    private var insideText = false
    private var insideBackground = false
    var shapes: [PPTXShapeText] = []
    var backgroundColor: String?
    var imageRelationshipIDs: [String] = []

    init(data: Data) { parser = XMLParser(data: data) }
    func parse() -> Bool { parser.delegate = self; return parser.parse() }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        switch name {
        case "sp": currentShape = PPTXShapeText(id: UUID(), isTitle: false, text: "")
        case "ph":
            if let type = attributeDict["type"] {
                currentShape?.placeholderType = type
                if type == "title" || type == "ctrTitle" { currentShape?.isTitle = true }
            }
        case "p": if currentShape?.text.isEmpty == false { currentShape?.text += "\n" }
        case "t": if currentShape != nil { insideText = true }
        case "blip":
            if let relationshipID = attributeDict.first(where: { $0.key == "embed" || $0.key.hasSuffix(":embed") })?.value {
                imageRelationshipIDs.append(relationshipID)
            }
        case "bg": insideBackground = true
        case "srgbClr":
            if insideBackground, backgroundColor == nil { backgroundColor = attributeDict["val"] }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideText { currentShape?.text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName.split(separator: ":").last.map(String.init) ?? elementName {
        case "t": insideText = false
        case "sp": if let currentShape { shapes.append(currentShape) }; currentShape = nil
        case "bg": insideBackground = false
        default: break
        }
    }
}

private struct PPTXShapeText {
    let id: UUID
    var isTitle: Bool
    var text: String
    var placeholderType: String? = nil
}
