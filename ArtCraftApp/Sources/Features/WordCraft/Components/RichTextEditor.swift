
import SwiftUI
import UIKit

struct RichTextEditor: UIViewRepresentable {

    // MARK: - Document Bindings

    @Binding var attributedText: NSAttributedString
    @Binding var selectedRange: NSRange
    @Binding var contentHeight: CGFloat

    // MARK: - Formatting Bindings

    @Binding var isBold: Bool
    @Binding var isItalic: Bool
    @Binding var isUnderlined: Bool

    @Binding var fontSize: Double
    @Binding var fontFamily: String

    @Binding var paragraphAlignment: NSTextAlignment
    @Binding var lineSpacing: Double
    @Binding var paragraphIndent: Double

    // MARK: - Page Layout

    @Binding var marginPreset: WordMarginPreset

    let minimumPageHeight: CGFloat

    // MARK: - Coordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Page Margins

    private var pageInsets: UIEdgeInsets {
        let margin = marginPreset.value

        return UIEdgeInsets(
            top: margin,
            left: margin,
            bottom: margin,
            right: margin
        )
    }

    // MARK: - Create Text View

    func makeUIView(context: Context) -> UITextView {

        let textView = UITextView()

        textView.delegate = context.coordinator

        textView.isEditable = true
        textView.isSelectable = true
        textView.isScrollEnabled = false

        textView.backgroundColor = .white
        textView.textColor = .black

        textView.textContainerInset = pageInsets
        textView.textContainer.widthTracksTextView = true

        textView.attributedText = attributedText
        textView.typingAttributes = makeTypingAttributes()

        textView.setContentCompressionResistancePriority(
            .defaultLow,
            for: .vertical
        )

        textView.layoutIfNeeded()

        updateContentHeight(textView)

        return textView
    }

    // MARK: - Update Text View

    func updateUIView(
        _ uiView: UITextView,
        context: Context
    ) {

        context.coordinator.parent = self

        // Update page margins

        if uiView.textContainerInset != pageInsets {
            uiView.textContainerInset = pageInsets
        }

        // Update document content

        if !uiView.attributedText.isEqual(to: attributedText) {

            let safeLocation = min(
                selectedRange.location,
                attributedText.length
            )

            let safeLength = min(
                selectedRange.length,
                attributedText.length - safeLocation
            )

            let requestedSelection = NSRange(
                location: safeLocation,
                length: safeLength
            )

            context.coordinator.isUpdating = true

            uiView.attributedText = attributedText
            uiView.selectedRange = requestedSelection

            context.coordinator.isUpdating = false
        }

        // Update typing attributes

        uiView.typingAttributes = makeTypingAttributes()

        uiView.layoutIfNeeded()

        updateContentHeight(uiView)
    }

    // MARK: - Update Content Height

    fileprivate func updateContentHeight(_ textView: UITextView) {

        textView.layoutIfNeeded()

        let calculatedHeight = max(
            minimumPageHeight,
            ceil(textView.contentSize.height)
        )

        if abs(contentHeight - calculatedHeight) > 1 {

            DispatchQueue.main.async {
                contentHeight = calculatedHeight
            }
        }
    }

    // MARK: - Typing Attributes

    private func makeTypingAttributes() -> [NSAttributedString.Key: Any] {

        let fontNames: [String: String] = [
            "Arial": "ArialMT",
            "Helvetica": "Helvetica",
            "Times New Roman": "TimesNewRomanPSMT",
            "Georgia": "Georgia",
            "Courier New": "CourierNewPSMT"
        ]

        let size = CGFloat(fontSize)

        let baseFont: UIFont

        if fontFamily == "System" {

            baseFont = UIFont.systemFont(ofSize: size)

        } else {

            let name = fontNames[fontFamily] ?? fontFamily

            baseFont = UIFont(
                name: name,
                size: size
            ) ?? UIFont.systemFont(ofSize: size)
        }

        // Font Traits

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
                    size: size
                )
            } ?? baseFont

        // Paragraph Style

        let paragraphStyle = NSMutableParagraphStyle()

        paragraphStyle.alignment = paragraphAlignment
        paragraphStyle.lineHeightMultiple = CGFloat(lineSpacing)

        paragraphStyle.headIndent = CGFloat(paragraphIndent)
        paragraphStyle.firstLineHeadIndent = CGFloat(paragraphIndent)

        // Attributes

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

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate {

        var parent: RichTextEditor
        var isUpdating = false

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        // MARK: Text Changed

        func textViewDidChange(_ textView: UITextView) {

            guard !isUpdating else {
                return
            }

            parent.attributedText = textView.attributedText
            parent.selectedRange = textView.selectedRange

            parent.updateContentHeight(textView)
        }

        // MARK: Selection Changed

        func textViewDidChangeSelection(_ textView: UITextView) {

            guard !isUpdating else {
                return
            }

            parent.selectedRange = textView.selectedRange
        }
    }
}

