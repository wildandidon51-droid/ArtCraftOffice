
import SwiftUI
import UIKit

struct WordCraftView: View {

    // MARK: - Document State

    @State private var documentTitle = "Untitled Document"

    @State private var attributedText = NSAttributedString(string: "")
    @State private var selectedRange = NSRange(location: 0, length: 0)

    @State private var contentHeight: CGFloat = 842

    // MARK: - Ribbon State

    @State private var selectedTab: WordRibbonTab = .home

    @State private var fontFamily = "System"
    @State private var fontSize: Double = 16

    @State private var isBold = false
    @State private var isItalic = false
    @State private var isUnderlined = false

    @State private var paragraphAlignment: NSTextAlignment = .left
    @State private var lineSpacing: Double = 1.0
    @State private var paragraphIndent: Double = 0

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

                    Text(documentTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            }
            .padding()

            Divider()

            // Ribbon Toolbar

            WordRibbon(
                selectedTab: $selectedTab,

                isBold: $isBold,
                isItalic: $isItalic,
                isUnderlined: $isUnderlined,

                fontSize: $fontSize,
                fontFamily: $fontFamily,

                paragraphAlignment: $paragraphAlignment,
                lineSpacing: $lineSpacing,

                paperSize: $paperSize,
                pageOrientation: $pageOrientation,
                marginPreset: $marginPreset,

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

                        fontSize: $fontSize,
                        fontFamily: $fontFamily,

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
                    .background(Color.white)
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
        }
        .background(
            Color(uiColor: .systemBackground)
        )
        .navigationTitle(documentTitle)
        .navigationBarTitleDisplayMode(.inline)

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

        .onChange(of: fontSize) { _, value in
            applyFontSize(value)
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
    }

    // MARK: - New Document

    private func createNewDocument() {

        documentTitle = "Untitled Document"

        attributedText = NSAttributedString(string: "")
        selectedRange = NSRange(location: 0, length: 0)

        isBold = false
        isItalic = false
        isUnderlined = false

        fontFamily = "System"
        fontSize = 16

        paragraphAlignment = .left
        lineSpacing = 1.0
        paragraphIndent = 0

        paperSize = .a4
        pageOrientation = .portrait
        marginPreset = .normal

        contentHeight = 842

        selectedTab = .home
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
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraphStyle
        ]

        if isUnderlined {

            attributes[.underlineStyle] =
                NSUnderlineStyle.single.rawValue
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
