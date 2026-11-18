
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct WordCraftView: View {
    @Environment(\.undoManager) private var undoManager

    // MARK: - Document State

    @State private var documentTitle = "Untitled Document"
    @State private var activeDocument = WordDocument()
    @StateObject private var documentStore = WordDocumentStore()
    @State private var showingDocuments = false
    @State private var showingImporter = false
    @State private var showingFindReplace = false
    @State private var exportURL: URL?
    @State private var pendingAutoSave: Task<Void, Never>?
    @State private var findQuery = ""
    @State private var replacementQuery = ""
    @State private var findStatus = ""

    @State private var attributedText = NSAttributedString(string: "")
    @State private var selectedRange = NSRange(location: 0, length: 0)

    @State private var contentHeight: CGFloat = 842

    // MARK: - Ribbon State

    @State private var selectedTab: WordRibbonTab = .home

    @State private var fontFamily = "System"
    @State private var fontSize: Double = 16
    @State private var textStyle = "Normal"

    @State private var isBold = false
    @State private var isItalic = false
    @State private var isUnderlined = false
    @State private var isHighlighted = false

    @State private var paragraphAlignment: NSTextAlignment = .left
    @State private var lineSpacing: Double = 1.0
    @State private var paragraphIndent: Double = 0
    @State private var textColor: Color = .black
    @State private var highlightColor: Color = .yellow

    // MARK: - Page Layout State

    @State private var paperSize: WordPaperSize = .a4
    @State private var pageOrientation: WordPageOrientation = .portrait
    @State private var marginPreset: WordMarginPreset = .normal

    // MARK: - Page Dimensions

    private var pageDimensions: CGSize {

        let dimensions = paperSize.dimensions

        if pageOrientation == .landscape {
            return CGSize(
                width: dimensions.height,
                height: dimensions.width
            )
        }

        return dimensions
    }

    // MARK: - Main View

    var body: some View {

        VStack(spacing: 0) {

            // Document Header

            HStack {

                VStack(alignment: .leading, spacing: 4) {

                    Text("WordCraft")
                        .font(.headline)

                    TextField("Document title", text: $documentTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textFieldStyle(.plain)
                }

                Spacer()

                Button {
                    createNewDocument()
                } label: {
                    Label(
                        "New",
                        systemImage: "doc.badge.plus"
                    )
                }
                .buttonStyle(.bordered)

                Button {
                    saveCurrentDocument()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showingDocuments = true
                } label: {
                    Label("Documents", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button {
                    showingImporter = true
                } label: {
                    Label("Open", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Menu {
                        Button("Word document (.docx)", systemImage: "doc.text", action: prepareDocxExport)
                        Button("Rich Text (.rtf)", systemImage: "text.alignleft", action: prepareExport)
                        Button("PDF (.pdf)", systemImage: "doc.richtext", action: preparePDFExport)
                    } label: { Label("Export", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                }

                Button {
                    printDocument()
                } label: {
                    Label("Print", systemImage: "printer")
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // Ribbon Toolbar

            WordRibbon(
                selectedTab: $selectedTab,

                isBold: $isBold,
                isItalic: $isItalic,
                isUnderlined: $isUnderlined,
                isHighlighted: $isHighlighted,

                fontSize: $fontSize,
                fontFamily: $fontFamily,
                textStyle: $textStyle,
                textColor: $textColor,
                highlightColor: $highlightColor,

                paragraphAlignment: $paragraphAlignment,
                lineSpacing: $lineSpacing,

                paperSize: $paperSize,
                pageOrientation: $pageOrientation,
                marginPreset: $marginPreset,
                documentText: attributedText.string,

                onBullets: {
                    insertListPrefix("• ")
                },

                onNumbering: {
                    insertNumbering()
                },

                onDecreaseIndent: {
                    changeIndent(by: -20)
                },

                onIncreaseIndent: {
                    changeIndent(by: 20)
                },

                onInsertPageBreak: {
                    insertPageBreak()
                },

                onFindReplace: {
                    showingFindReplace = true
                },

                onUndo: {
                    undoManager?.undo()
                },

                onRedo: {
                    undoManager?.redo()
                }
            )

            Divider()

            // Document Workspace

            ScrollView([.horizontal, .vertical]) {

                VStack {

                    RichTextEditor(
                        attributedText: $attributedText,
                        selectedRange: $selectedRange,
                        contentHeight: $contentHeight,

                        isBold: $isBold,
                        isItalic: $isItalic,
                        isUnderlined: $isUnderlined,
                        isHighlighted: $isHighlighted,

                        fontSize: $fontSize,
                        fontFamily: $fontFamily,
                        textColor: $textColor,
                        highlightColor: $highlightColor,

                        paragraphAlignment: $paragraphAlignment,
                        lineSpacing: $lineSpacing,
                        paragraphIndent: $paragraphIndent,

                        marginPreset: $marginPreset,

                        minimumPageHeight: pageDimensions.height
                    )
                    .frame(
                        width: pageDimensions.width,
                        height: contentHeight
                    )
                    .background(PageCanvasBackground(pageHeight: pageDimensions.height))
                    .clipShape(
                        RoundedRectangle(cornerRadius: 2)
                    )
                    .shadow(
                        color: .black.opacity(0.15),
                        radius: 8,
                        x: 0,
                        y: 3
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            }
            .background(
                Color(uiColor: .systemGroupedBackground)
            )

            HStack(spacing: 18) {
                Label("\(max(1, Int(ceil(contentHeight / pageDimensions.height))) pages", systemImage: "doc.text")
                Label("\(attributedText.string.split { $0.isWhitespace || $0.isNewline }.count) words", systemImage: "text.word.spacing")
                Spacer()
                Text(documentStore.lastError ?? "Saved on this iPad")
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(documentStore.lastError == nil ? .secondary : .red)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.bar)
        }
        .background(
            Color(uiColor: .systemBackground)
        )
        .navigationTitle(documentTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingDocuments) {
            NavigationStack {
                List {
                    ForEach(documentStore.documents) { document in
                        Button {
                            openDocument(document)
                            showingDocuments = false
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(document.title).font(.headline).foregroundStyle(.primary)
                                Text(document.content.isEmpty ? "No content" : document.content)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                Text(document.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .onDelete(perform: documentStore.delete)
                }
                .overlay {
                    if documentStore.documents.isEmpty {
                        ContentUnavailableView("No saved documents", systemImage: "doc.text", description: Text("Save a document to find it here."))
                    }
                }
                .navigationTitle("Documents")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showingDocuments = false }
                    }
                }
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.rtf, .plainText, UTType(filenameExtension: "docx") ?? .data], allowsMultipleSelection: false) { result in
            do {
                pendingAutoSave?.cancel()
                saveCurrentDocument()
                let url = try result.get().first!
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                if url.pathExtension.lowercased() == "docx" {
                    let imported = try WordDocxCodec.decodeDocument(data)
                    attributedText = imported.attributedText
                    paperSize = imported.paperSize
                    pageOrientation = imported.pageOrientation
                    marginPreset = imported.marginPreset
                } else if url.pathExtension.lowercased() == "rtf",
                   let richText = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
                    attributedText = richText
                } else if let text = String(data: data, encoding: .utf8) {
                    attributedText = NSAttributedString(string: text, attributes: typingAttributes())
                } else {
                    throw CocoaError(.fileReadInapplicableStringEncoding)
                }
                activeDocument = WordDocument(
                    title: url.deletingPathExtension().lastPathComponent,
                    paperSize: paperSize,
                    pageOrientation: pageOrientation,
                    marginPreset: marginPreset
                )
                documentTitle = activeDocument.title
                selectedRange = NSRange(location: 0, length: 0)
                contentHeight = max(842, pageDimensions.height)
                exportURL = nil
                saveCurrentDocument()
            } catch {
                documentStore.reportError("Could not open the selected document. The current draft is still open.")
            }
        }
        .sheet(isPresented: $showingFindReplace) {
            NavigationStack {
                Form {
                    Section("Find") {
                        TextField("Search text", text: $findQuery)
                            .submitLabel(.search)
                            .onSubmit(findNext)
                        Button("Find next", systemImage: "magnifyingglass", action: findNext)
                    }
                    Section("Replace") {
                        TextField("Replace with", text: $replacementQuery)
                        Button("Replace all", systemImage: "text.badge.plus", action: replaceAll)
                            .disabled(findQuery.isEmpty)
                    }
                    if !findStatus.isEmpty {
                        Section { Text(findStatus).foregroundStyle(.secondary) }
                    }
                }
                .navigationTitle("Find and replace")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showingFindReplace = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }

        // MARK: - Formatting Observers

        .onChange(of: isBold) { _, value in
            applyFontTrait(.traitBold, enabled: value)
        }

        .onChange(of: isItalic) { _, value in
            applyFontTrait(.traitItalic, enabled: value)
        }

        .onChange(of: isUnderlined) { _, value in
            applyUnderline(enabled: value)
        }

        .onChange(of: isHighlighted) { _, value in
            applyHighlight(enabled: value)
        }

        .onChange(of: textColor) { _, color in
            applyTextColor(color)
        }

        .onChange(of: highlightColor) { _, color in
            if isHighlighted { applyHighlight(color: color) }
        }

        .onChange(of: fontSize) { _, value in
            applyFontSize(value)
        }

        .onChange(of: textStyle) { _, style in
            applyTextStyle(style)
        }

        .onChange(of: fontFamily) { _, value in
            applyFontFamily(value)
        }

        .onChange(of: paragraphAlignment) { _, value in
            applyParagraphAlignment(value)
        }

        .onChange(of: lineSpacing) { _, value in
            applyLineSpacing(value)
        }
        .onChange(of: attributedText) { _, _ in
            scheduleAutoSave()
        }
        .onChange(of: documentTitle) { _, _ in
            scheduleAutoSave()
        }
        .onChange(of: paperSize) { _, _ in scheduleAutoSave() }
        .onChange(of: pageOrientation) { _, _ in scheduleAutoSave() }
        .onChange(of: marginPreset) { _, _ in scheduleAutoSave() }
        .onDisappear {
            pendingAutoSave?.cancel()
            saveCurrentDocument()
        }
    }

    // MARK: - New Document

    private func createNewDocument() {

        pendingAutoSave?.cancel()
        saveCurrentDocument()
        activeDocument = WordDocument()
        documentTitle = "Untitled Document"

        attributedText = NSAttributedString(string: "")
        selectedRange = NSRange(location: 0, length: 0)

        isBold = false
        isItalic = false
        isUnderlined = false
        isHighlighted = false
        textColor = .black
        highlightColor = .yellow

        fontFamily = "System"
        fontSize = 16
        textStyle = "Normal"

        paragraphAlignment = .left
        lineSpacing = 1.0
        paragraphIndent = 0

        paperSize = .a4
        pageOrientation = .portrait
        marginPreset = .normal

        contentHeight = 842

        selectedTab = .home
    }

    private func saveCurrentDocument() {
        let isExisting = documentStore.documents.contains { $0.id == activeDocument.id }
        let isUntouchedDraft = attributedText.length == 0 && documentTitle == "Untitled Document" && !isExisting
        guard !isUntouchedDraft else { return }
        activeDocument.update(
            title: documentTitle,
            text: attributedText,
            paperSize: paperSize,
            pageOrientation: pageOrientation,
            marginPreset: marginPreset
        )
        documentTitle = activeDocument.title
        documentStore.save(activeDocument)
    }

    private func scheduleAutoSave() {
        pendingAutoSave?.cancel()
        pendingAutoSave = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            saveCurrentDocument()
        }
    }

    private func openDocument(_ document: WordDocument) {
        pendingAutoSave?.cancel()
        saveCurrentDocument()
        activeDocument = document
        documentTitle = document.title
        attributedText = document.attributedContent
        paperSize = document.paperSize
        pageOrientation = document.pageOrientation
        marginPreset = document.marginPreset
        selectedRange = NSRange(location: 0, length: 0)
        contentHeight = max(842, pageDimensions.height)
        selectedTab = .home
    }

    private func prepareExport() {
        let data = try? attributedText.data(
            from: NSRange(location: 0, length: attributedText.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        guard let data else { return }
        let safeName = documentTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled Document" : documentTitle
        let fileName = safeName.replacingOccurrences(of: "/", with: "-") + ".rtf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            exportURL = nil
        }
    }

    private func prepareDocxExport() {
        let safeName = documentTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled Document" : documentTitle
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeFileName(safeName) + ".docx")
        do {
            let data = try WordDocxCodec.encode(
                attributedText,
                paperSize: paperSize,
                pageOrientation: pageOrientation,
                marginPreset: marginPreset
            )
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            exportURL = nil
            documentStore.reportError("Could not export the DOCX document.")
        }
    }

    private func preparePDFExport() {
        let pageSize = pageDimensions
        let pageRect = CGRect(origin: .zero, size: pageSize)
        let margin = marginPreset.value
        let contentSize = CGSize(
            width: max(1, pageSize.width - margin * 2),
            height: max(1, pageSize.height - margin * 2)
        )
        let storage = NSTextStorage(attributedString: attributedText)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let pdfData = renderer.pdfData { context in
            var nextGlyph = 0
            let glyphCount = layout.numberOfGlyphs
            repeat {
                let container = NSTextContainer(size: contentSize)
                container.lineFragmentPadding = 0
                layout.addTextContainer(container)
                layout.ensureLayout(for: container)
                let range = layout.glyphRange(for: container)
                guard range.length > 0 || glyphCount == 0 else { break }
                context.beginPage()
                UIColor.white.setFill()
                context.fill(pageRect)
                let origin = CGPoint(x: margin, y: margin)
                layout.drawBackground(forGlyphRange: range, at: origin)
                layout.drawGlyphs(forGlyphRange: range, at: origin)
                nextGlyph = NSMaxRange(range)
                if glyphCount == 0 { break }
            } while nextGlyph < glyphCount
        }
        let fileName = safeFileName(documentTitle) + ".pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do { try pdfData.write(to: url, options: .atomic); exportURL = url }
        catch { exportURL = nil }
    }

    private func printDocument() {
        preparePDFExport()
        guard let exportURL else { return }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = documentTitle
        info.outputType = .general
        controller.printInfo = info
        controller.printingItem = exportURL
        controller.present(animated: true, completionHandler: nil)
    }

    private func findNext() {
        guard !findQuery.isEmpty else { findStatus = "Enter text to find."; return }
        let source = attributedText.string as NSString
        guard source.length > 0 else { findStatus = "No match found."; return }
        let start = min(NSMaxRange(selectedRange), source.length)
        let tail = NSRange(location: start, length: source.length - start)
        var match = source.range(of: findQuery, options: [.caseInsensitive], range: tail)
        if match.location == NSNotFound {
            match = source.range(of: findQuery, options: [.caseInsensitive], range: NSRange(location: 0, length: start))
        }
        guard match.location != NSNotFound else { findStatus = "No match found."; return }
        selectedRange = match
        findStatus = "Match at character \(match.location + 1)."
    }

    private func replaceAll() {
        guard !findQuery.isEmpty else { return }
        let source = attributedText.string as NSString
        var matches: [NSRange] = []
        var cursor = 0
        while cursor < source.length {
            let range = source.range(of: findQuery, options: [.caseInsensitive], range: NSRange(location: cursor, length: source.length - cursor))
            guard range.location != NSNotFound else { break }
            matches.append(range)
            cursor = NSMaxRange(range)
        }
        guard !matches.isEmpty else { findStatus = "No matches to replace."; return }
        let updated = NSMutableAttributedString(attributedString: attributedText)
        for range in matches.reversed() {
            updated.replaceCharacters(in: range, with: replacementQuery)
        }
        attributedText = updated
        selectedRange = NSRange(location: 0, length: 0)
        findStatus = "Replaced \(matches.count) occurrence(s)."
    }

    // MARK: - Page Break

    private func insertPageBreak() {

        let safeLocation = min(
            selectedRange.location,
            attributedText.length
        )

        let mutableText = NSMutableAttributedString(
            attributedString: attributedText
        )

        let pageBreak = NSAttributedString(
            string: "\n\u{000C}\n",
            attributes: typingAttributes()
        )

        mutableText.insert(
            pageBreak,
            at: safeLocation
        )

        attributedText = mutableText

        selectedRange = NSRange(
            location: safeLocation + pageBreak.length,
            length: 0
        )
    }

    // MARK: - Selected Paragraph Ranges

    private func selectedParagraphRanges() -> [NSRange] {

        let text = attributedText.string as NSString

        guard text.length > 0 else {
            return []
        }

        let start = min(
            selectedRange.location,
            text.length
        )

        let lastCharacter = selectedRange.length > 0
            ? min(
                NSMaxRange(selectedRange) - 1,
                text.length - 1
            )
            : min(
                start,
                text.length - 1
            )

        let firstRange = text.paragraphRange(
            for: NSRange(
                location: start,
                length: 0
            )
        )

        let lastRange = text.paragraphRange(
            for: NSRange(
                location: lastCharacter,
                length: 0
            )
        )

        var ranges: [NSRange] = []
        var currentRange = firstRange

        while true {

            ranges.append(currentRange)

            if currentRange.location == lastRange.location {
                break
            }

            let nextLocation = NSMaxRange(currentRange)

            if nextLocation >= text.length {
                break
            }

            currentRange = text.paragraphRange(
                for: NSRange(
                    location: nextLocation,
                    length: 0
                )
            )
        }

        return ranges
    }

    // MARK: - Insert Bullets

    private func insertListPrefix(_ prefix: String) {

        let ranges = selectedParagraphRanges()

        guard !ranges.isEmpty else {
            return
        }

        let mutableText = NSMutableAttributedString(
            attributedString: attributedText
        )

        var insertedLength = 0

        for range in ranges.reversed() {

            let currentString = (mutableText.string as NSString)
                .substring(with: range)

            if currentString.hasPrefix(prefix) {
                continue
            }

            let insertion = NSAttributedString(
                string: prefix,
                attributes: typingAttributes()
            )

            mutableText.insert(
                insertion,
                at: range.location
            )

            insertedLength += prefix.utf16.count
        }

        attributedText = mutableText

        if insertedLength > 0 {

            selectedRange = NSRange(
                location: min(
                    selectedRange.location + insertedLength,
                    mutableText.length
                ),
                length: selectedRange.length
            )
        }
    }

    // MARK: - Insert Numbering

    private func insertNumbering() {

        let ranges = selectedParagraphRanges()

        guard !ranges.isEmpty else {
            return
        }

        let mutableText = NSMutableAttributedString(
            attributedString: attributedText
        )

        var insertedLength = 0

        for (index, range) in ranges.enumerated().reversed() {

            let currentString = (mutableText.string as NSString)
                .substring(with: range)

            if currentString.range(
                of: #"^\d+\.\s"#,
                options: .regularExpression
            ) != nil {
                continue
            }

            let prefix = "\(index + 1). "

            let insertion = NSAttributedString(
                string: prefix,
                attributes: typingAttributes()
            )

            mutableText.insert(
                insertion,
                at: range.location
            )

            insertedLength += prefix.utf16.count
        }

        attributedText = mutableText

        if insertedLength > 0 {

            selectedRange = NSRange(
                location: min(
                    selectedRange.location + insertedLength,
                    mutableText.length
                ),
                length: selectedRange.length
            )
        }
    }

    // MARK: - Change Indentation

    private func changeIndent(by amount: Double) {

        let ranges = selectedParagraphRanges()

        guard !ranges.isEmpty else {
            return
        }

        let mutableText = NSMutableAttributedString(
            attributedString: attributedText
        )

        for range in ranges {

            let existingStyle = mutableText.attribute(
                .paragraphStyle,
                at: range.location,
                effectiveRange: nil
            ) as? NSParagraphStyle

            let paragraphStyle =
                existingStyle?.mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()

            let newIndent = max(
                0,
                min(
                    120,
                    paragraphStyle.headIndent + CGFloat(amount)
                )
            )

            let difference = newIndent - paragraphStyle.headIndent

            paragraphStyle.headIndent = newIndent
            paragraphStyle.firstLineHeadIndent += difference

            mutableText.addAttribute(
                .paragraphStyle,
                value: paragraphStyle,
                range: range
            )
        }

        paragraphIndent = max(
            0,
            min(
                120,
                paragraphIndent + amount
            )
        )

        attributedText = mutableText
    }

    // MARK: - Typing Attributes

    private func typingAttributes() -> [NSAttributedString.Key: Any] {

        let fontNames: [String: String] = [
            "Arial": "ArialMT",
            "Helvetica": "Helvetica",
            "Times New Roman": "TimesNewRomanPSMT",
            "Georgia": "Georgia",
            "Courier New": "CourierNewPSMT"
        ]

        let fontName = fontNames[fontFamily] ?? fontFamily

        let baseFont = fontFamily == "System"
            ? UIFont.systemFont(
                ofSize: CGFloat(fontSize)
            )
            : UIFont(
                name: fontName,
                size: CGFloat(fontSize)
            ) ?? UIFont.systemFont(
                ofSize: CGFloat(fontSize)
            )

        var traits = baseFont.fontDescriptor.symbolicTraits

        if isBold {
            traits.insert(.traitBold)
        }

        if isItalic {
            traits.insert(.traitItalic)
        }

        let finalFont = baseFont.fontDescriptor
            .withSymbolicTraits(traits)
            .map {
                UIFont(
                    descriptor: $0,
                    size: CGFloat(fontSize)
                )
            } ?? baseFont

        let paragraphStyle = NSMutableParagraphStyle()

        paragraphStyle.alignment = paragraphAlignment
        paragraphStyle.lineHeightMultiple = CGFloat(lineSpacing)

        paragraphStyle.headIndent = CGFloat(paragraphIndent)
        paragraphStyle.firstLineHeadIndent = CGFloat(paragraphIndent)

        var attributes: [NSAttributedString.Key: Any] = [
            .font: finalFont,
            .foregroundColor: UIColor(textColor),
            .paragraphStyle: paragraphStyle
        ]

        if isUnderlined {

            attributes[.underlineStyle] =
                NSUnderlineStyle.single.rawValue
        }

        if isHighlighted {
            attributes[.backgroundColor] = UIColor(highlightColor)
        }

        return attributes
    }

    // MARK: - Apply Font Trait

    private func applyFontTrait(
        _ trait: UIFontDescriptor.SymbolicTraits,
        enabled: Bool
    ) {

        guard selectedRange.length > 0 else {
            return
        }

        let mutableText = NSMutableAttributedString(
            attributedString: attributedText
        )

        let safeRange = NSIntersectionRange(
            selectedRange,
            NSRange(
                location: 0,
                length: mutableText.length
            )
        )

        guard safeRange.length > 0 else {
            return
        }

        mutableText.enumerateAttribute(
            .font,
            in: safeRange,
            options: []
        ) { value, range, _ in

            let oldFont = value as? UIFont
                ?? UIFont.systemFont(
                    ofSize: CGFloat(fontSize)
                )

            var traits = oldFont.fontDescriptor.symbolicTraits

            if enabled {
                traits.insert(trait)
            } else {
                traits.remove(trait)
            }

            let newFont = oldFont.fontDescriptor
                .withSymbolicTraits(traits)
                .map {
                    UIFont(
                        descriptor: $0,
                        size: oldFont.pointSize
                    )
                } ?? oldFont

            mutableText.addAttribute(
                .font,
                value: newFont,
                range: range
            )
        }

        attributedText = mutableText
    }

    private func applyTextStyle(_ style: String) {
        let size: Double
        let bold: Bool
        switch style {
        case "Title": size = 32; bold = true
        case "Heading 1": size = 26; bold = true
        case "Heading 2": size = 21; bold = true
        default: size = 16; bold = false
        }
        fontSize = size
        isBold = bold
    }

    // MARK: - Apply Underline

    private func applyUnderline(enabled: Bool) {

        guard selectedRange.length > 0 else {
            return
        }

        let mutableText = NSMutableAttributedString(
            attributedString: attributedText
        )

        let safeRange = NSIntersectionRange(
            selectedRange,
            NSRange(
                location: 0,
                length: mutableText.length
            )
        )

        guard safeRange.length > 0 else {
            return
        }

        if enabled {

            mutableText.addAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: safeRange
            )

        } else {

            mutableText.removeAttribute(
                .underlineStyle,
                range: safeRange
            )
        }

        attributedText = mutableText
    }

    private func applyTextColor(_ color: Color) {
        guard selectedRange.length > 0 else { return }
        let safeRange = NSIntersectionRange(selectedRange, NSRange(location: 0, length: attributedText.length))
        guard safeRange.length > 0 else { return }
        let updated = NSMutableAttributedString(attributedString: attributedText)
        updated.addAttribute(.foregroundColor, value: UIColor(color), range: safeRange)
        attributedText = updated
    }

    private func applyHighlight(enabled: Bool) {
        applyHighlight(color: enabled ? highlightColor : nil)
    }

    private func applyHighlight(color: Color?) {
        guard selectedRange.length > 0 else { return }
        let safeRange = NSIntersectionRange(selectedRange, NSRange(location: 0, length: attributedText.length))
        guard safeRange.length > 0 else { return }
        let updated = NSMutableAttributedString(attributedString: attributedText)
        if let color {
            updated.addAttribute(.backgroundColor, value: UIColor(color), range: safeRange)
        } else {
            updated.removeAttribute(.backgroundColor, range: safeRange)
        }
        attributedText = updated
    }

    // MARK: - Apply Font Size

    private func applyFontSize(_ size: Double) {

        guard selectedRange.length > 0 else {
            return
        }

        let mutableText = NSMutableAttributedString(
            attributedString: attributedText
        )

        let safeRange = NSIntersectionRange(
            selectedRange,
            NSRange(
                location: 0,
                length: mutableText.length
            )
        )

        guard safeRange.length > 0 else {
            return
        }

        mutableText.enumerateAttribute(
            .font,
            in: safeRange,
            options: []
        ) { value, range, _ in

            let oldFont = value as? UIFont
                ?? UIFont.systemFont(
                    ofSize: CGFloat(size)
                )

            let newFont = UIFont(
                descriptor: oldFont.fontDescriptor,
                size: CGFloat(size)
            )

            mutableText.addAttribute(
                .font,
                value: newFont,
                range: range
            )
        }

        attributedText = mutableText
    }

    // MARK: - Apply Font Family

    private func applyFontFamily(_ family: String) {

        guard selectedRange.length > 0 else {
            return
        }

        let mutableText = NSMutableAttributedString(
            attributedString: attributedText
        )

        let safeRange = NSIntersectionRange(
            selectedRange,
            NSRange(
                location: 0,
                length: mutableText.length
            )
        )

        guard safeRange.length > 0 else {
            return
        }

        let fontNames: [String: String] = [
            "Arial": "ArialMT",
            "Helvetica": "Helvetica",
            "Times New Roman": "TimesNewRomanPSMT",
            "Georgia": "Georgia",
            "Courier New": "CourierNewPSMT"
        ]

        mutableText.enumerateAttribute(
            .font,
            in: safeRange,
            options: []
        ) { value, range, _ in

            let oldFont = value as? UIFont
                ?? UIFont.systemFont(
                    ofSize: CGFloat(fontSize)
                )

            let newFont: UIFont

            if family == "System" {

                newFont = UIFont.systemFont(
                    ofSize: oldFont.pointSize
                )

            } else {

                let name = fontNames[family] ?? family

                newFont = UIFont(
                    name: name,
                    size: oldFont.pointSize
                ) ?? oldFont
            }

            mutableText.addAttribute(
                .font,
                value: newFont,
                range: range
            )
        }

        attributedText = mutableText
    }

    // MARK: - Apply Paragraph Alignment

    private func applyParagraphAlignment(
        _ alignment: NSTextAlignment
    ) {

        let ranges = allParagraphRanges()

        guard !ranges.isEmpty else {
            return
        }

        let mutableText = NSMutableAttributedString(
            attributedString: attributedText
        )

        for range in ranges {

            let existingStyle = mutableText.attribute(
                .paragraphStyle,
                at: range.location,
                effectiveRange: nil
            ) as? NSParagraphStyle

            let style =
                existingStyle?.mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()

            style.alignment = alignment

            mutableText.addAttribute(
                .paragraphStyle,
                value: style,
                range: range
            )
        }

        attributedText = mutableText
    }

    // MARK: - Apply Line Spacing

    private func applyLineSpacing(_ spacing: Double) {

        let ranges = allParagraphRanges()

        guard !ranges.isEmpty else {
            return
        }

        let mutableText = NSMutableAttributedString(
            attributedString: attributedText
        )

        for range in ranges {

            let existingStyle = mutableText.attribute(
                .paragraphStyle,
                at: range.location,
                effectiveRange: nil
            ) as? NSParagraphStyle

            let style =
                existingStyle?.mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()

            style.lineHeightMultiple = CGFloat(spacing)

            mutableText.addAttribute(
                .paragraphStyle,
                value: style,
                range: range
            )
        }

        attributedText = mutableText
    }

    // MARK: - All Paragraph Ranges

    private func allParagraphRanges() -> [NSRange] {

        let text = attributedText.string as NSString

        guard text.length > 0 else {
            return []
        }

        var ranges: [NSRange] = []
        var location = 0

        while location < text.length {

            let range = text.paragraphRange(
                for: NSRange(
                    location: location,
                    length: 0
                )
            )

            ranges.append(range)

            location = NSMaxRange(range)
        }

        return ranges
    }
}

private struct PageCanvasBackground: View {
    let pageHeight: CGFloat

    var body: some View {
        Canvas { context, size in
            guard pageHeight > 0 else { return }
            let pageCount = max(1, Int(ceil(size.height / pageHeight)))
            for page in 0..<pageCount {
                let y = CGFloat(page) * pageHeight
                let rect = CGRect(x: 0, y: y, width: size.width, height: min(pageHeight, size.height - y))
                guard rect.height > 0 else { continue }
                context.fill(Path(rect), with: .color(.white))
                context.stroke(
                    Path(rect.insetBy(dx: 0.5, dy: 0.5)),
                    with: .color(Color(uiColor: .separator).opacity(0.5)),
                    lineWidth: 1
                )
            }
        }
        .accessibilityHidden(true)
    }
}
