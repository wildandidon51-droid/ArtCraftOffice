
import SwiftUI
import UIKit

// MARK: - Page Layout Models

enum WordRibbonTab: String, CaseIterable {
    case home = "Home"
    case insert = "Insert"
    case layout = "Layout"
    case review = "Review"
    case view = "View"
}

enum WordPaperSize: String, CaseIterable, Identifiable, Codable {
    case a4 = "A4"
    case letter = "Letter"
    case legal = "Legal"

    var id: String { rawValue }

    var dimensions: CGSize {
        switch self {
        case .a4:
            return CGSize(width: 595, height: 842)
        case .letter:
            return CGSize(width: 612, height: 792)
        case .legal:
            return CGSize(width: 612, height: 1008)
        }
    }
}

enum WordPageOrientation: String, CaseIterable, Identifiable, Codable {
    case portrait = "Portrait"
    case landscape = "Landscape"

    var id: String { rawValue }
}

enum WordMarginPreset: String, CaseIterable, Identifiable, Codable {
    case normal = "Normal"
    case narrow = "Narrow"
    case moderate = "Moderate"
    case wide = "Wide"

    var id: String { rawValue }

    var value: CGFloat {
        switch self {
        case .normal:
            return 72
        case .narrow:
            return 36
        case .moderate:
            return 54
        case .wide:
            return 90
        }
    }
}

// MARK: - Word Ribbon

struct WordRibbon: View {

    @Binding var selectedTab: WordRibbonTab

    @Binding var isBold: Bool
    @Binding var isItalic: Bool
    @Binding var isUnderlined: Bool
    @Binding var isHighlighted: Bool

    @Binding var fontSize: Double
    @Binding var fontFamily: String
    @Binding var textStyle: String
    @Binding var textColor: Color
    @Binding var highlightColor: Color

    @Binding var paragraphAlignment: NSTextAlignment
    @Binding var lineSpacing: Double

    @Binding var paperSize: WordPaperSize
    @Binding var pageOrientation: WordPageOrientation
    @Binding var marginPreset: WordMarginPreset
    var documentText: String

    var onBullets: () -> Void
    var onNumbering: () -> Void
    var onDecreaseIndent: () -> Void
    var onIncreaseIndent: () -> Void
    var onInsertPageBreak: () -> Void
    var onFindReplace: () -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            HStack(spacing: 24) {
                ForEach(WordRibbonTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 8) {
                            Text(tab.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(
                                    selectedTab == tab
                                    ? Color.accentColor
                                    : Color.primary
                                )

                            Capsule()
                                .fill(
                                    selectedTab == tab
                                    ? Color.accentColor
                                    : Color.clear
                                )
                                .frame(height: 3)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            switch selectedTab {
            case .home:
                homeToolbar
            case .layout:
                layoutToolbar
            case .insert:
                insertToolbar
            case .review:
                reviewToolbar
            case .view:
                viewToolbar
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var reviewToolbar: some View {
        HStack(spacing: 28) {
            Label("\(documentText.split { $0.isWhitespace || $0.isNewline }.count) words", systemImage: "text.word.spacing")
            Label("\(documentText.count) characters", systemImage: "character.cursor.ibeam")
            Button(action: onFindReplace) {
                Label("Find and replace", systemImage: "magnifyingglass")
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(minHeight: 48)
    }

    private var viewToolbar: some View {
        HStack(spacing: 12) {
            Label("Page view", systemImage: "doc.text")
            Text(paperSize.rawValue + " · " + pageOrientation.rawValue)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(minHeight: 48)
    }

    // MARK: - Home Toolbar

    private var homeToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {

                VStack(spacing: 6) {
                    Text("History").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button(action: onUndo) { Image(systemName: "arrow.uturn.backward") }.help("Undo")
                        Button(action: onRedo) { Image(systemName: "arrow.uturn.forward") }.help("Redo")
                    }
                }

                Divider().frame(height: 45)

                VStack(spacing: 6) {
                    Text("Text color").font(.caption).foregroundStyle(.secondary)
                    ColorPicker("Text color", selection: $textColor, supportsOpacity: false)
                        .labelsHidden().frame(width: 40)
                }

                Divider().frame(height: 45)

                VStack(spacing: 6) {
                    Text("Highlight").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ColorPicker("Highlight color", selection: $highlightColor, supportsOpacity: false).labelsHidden().frame(width: 38)
                        formatButton("highlighter", isActive: isHighlighted) { isHighlighted.toggle() }
                    }
                }

                Divider().frame(height: 45)

                VStack(spacing: 6) {
                    Text("Styles").font(.caption).foregroundStyle(.secondary)
                    Picker("Style", selection: $textStyle) {
                        Text("Normal").tag("Normal")
                        Text("Title").tag("Title")
                        Text("Heading 1").tag("Heading 1")
                        Text("Heading 2").tag("Heading 2")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130)
                }

                Divider().frame(height: 45)

                VStack(spacing: 6) {
                    Text("Font")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Font", selection: $fontFamily) {
                        Text("System").tag("System")
                        Text("Arial").tag("Arial")
                        Text("Helvetica").tag("Helvetica")
                        Text("Times New Roman").tag("Times New Roman")
                        Text("Georgia").tag("Georgia")
                        Text("Courier New").tag("Courier New")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }

                Divider().frame(height: 45)

                VStack(spacing: 6) {
                    Text("Font Size")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button {
                            fontSize = max(8, fontSize - 1)
                        } label: {
                            Image(systemName: "minus")
                        }

                        Text("\(Int(fontSize))")
                            .font(.subheadline.monospacedDigit())
                            .frame(width: 30)

                        Button {
                            fontSize = min(72, fontSize + 1)
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }

                Divider().frame(height: 45)

                VStack(spacing: 6) {
                    Text("Font Style")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        formatButton("bold", isActive: isBold) {
                            isBold.toggle()
                        }

                        formatButton("italic", isActive: isItalic) {
                            isItalic.toggle()
                        }

                        formatButton("underline", isActive: isUnderlined) {
                            isUnderlined.toggle()
                        }
                    }
                }

                Divider().frame(height: 45)

                VStack(spacing: 6) {
                    Text("Paragraph")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        alignmentButton("text.align.left", alignment: .left)
                        alignmentButton("text.align.center", alignment: .center)
                        alignmentButton("text.align.right", alignment: .right)
                        alignmentButton("text.align.justify", alignment: .justified)
                    }
                }

                Divider().frame(height: 45)

                VStack(spacing: 6) {
                    Text("Line Spacing")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Line Spacing", selection: $lineSpacing) {
                        Text("1.0").tag(1.0)
                        Text("1.15").tag(1.15)
                        Text("1.5").tag(1.5)
                        Text("2.0").tag(2.0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }

                Divider().frame(height: 45)

                VStack(spacing: 6) {
                    Text("Lists")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        formatButton("list.bullet", isActive: false) {
                            onBullets()
                        }

                        formatButton("list.number", isActive: false) {
                            onNumbering()
                        }
                    }
                }

                Divider().frame(height: 45)

                VStack(spacing: 6) {
                    Text("Indent")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        formatButton("decrease.indent", isActive: false) {
                            onDecreaseIndent()
                        }

                        formatButton("increase.indent", isActive: false) {
                            onIncreaseIndent()
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Layout Toolbar

    private var layoutToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {

                VStack(spacing: 6) {
                    Image(systemName: "doc")
                        .font(.title2)

                    Text("Paper Size")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Paper Size", selection: $paperSize) {
                        ForEach(WordPaperSize.allCases) { size in
                            Text(size.rawValue).tag(size)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Divider().frame(height: 65)

                VStack(spacing: 6) {
                    Image(systemName: "rectangle.portrait")
                        .font(.title2)

                    Text("Orientation")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Orientation", selection: $pageOrientation) {
                        ForEach(WordPageOrientation.allCases) { orientation in
                            Text(orientation.rawValue).tag(orientation)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Divider().frame(height: 65)

                VStack(spacing: 6) {
                    Image(systemName: "arrow.left.and.right")
                        .font(.title2)

                    Text("Margins")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Margins", selection: $marginPreset) {
                        ForEach(WordMarginPreset.allCases) { margin in
                            Text(margin.rawValue).tag(margin)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 75)
    }

    // MARK: - Insert Toolbar

    private var insertToolbar: some View {
        HStack(spacing: 20) {
            Button {
                onInsertPageBreak()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "doc.badge.plus")
                        .font(.title2)

                    Text("Page Break")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(minHeight: 65)
    }

    // MARK: - Format Button

    private func formatButton(
        _ icon: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(
                    isActive ? Color.white : Color.primary
                )
                .frame(width: 34, height: 34)
                .background(
                    isActive ? Color.accentColor : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Alignment Button

    private func alignmentButton(
        _ icon: String,
        alignment: NSTextAlignment
    ) -> some View {
        Button {
            paragraphAlignment = alignment
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(
                    paragraphAlignment == alignment
                    ? Color.white
                    : Color.primary
                )
                .frame(width: 34, height: 34)
                .background(
                    paragraphAlignment == alignment
                    ? Color.accentColor
                    : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
