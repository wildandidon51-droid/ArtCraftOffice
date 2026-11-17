
import SwiftUI

enum WordRibbonTab: String, CaseIterable {
    case home = "Home"
    case insert = "Insert"
    case layout = "Layout"
    case review = "Review"
    case view = "View"
}

struct WordRibbon: View {

    @Binding var selectedTab: WordRibbonTab
    @Binding var isBold: Bool
    @Binding var isItalic: Bool
    @Binding var isUnderlined: Bool
    @Binding var fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Ribbon Tabs

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

            // Ribbon Content

            if selectedTab == .home {
                homeToolbar
            } else {
                Text("\(selectedTab.rawValue) tools coming soon")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var homeToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {

                // Font Size

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

                Divider()
                    .frame(height: 45)

                // Text Formatting

                VStack(spacing: 6) {
                    Text("Font Style")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        formatButton(
                            "bold",
                            isActive: isBold
                        ) {
                            isBold.toggle()
                        }

                        formatButton(
                            "italic",
                            isActive: isItalic
                        ) {
                            isItalic.toggle()
                        }

                        formatButton(
                            "underline",
                            isActive: isUnderlined
                        ) {
                            isUnderlined.toggle()
                        }
                    }
                }

                Divider()
                    .frame(height: 45)

                // Paragraph

                VStack(spacing: 6) {
                    Text("Paragraph")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Image(systemName: "text.align.left")
                        Image(systemName: "text.align.center")
                        Image(systemName: "text.align.right")
                        Image(systemName: "list.bullet")
                    }
                    .font(.title3)
                    .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func formatButton(
        _ icon: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .frame(width: 34, height: 34)
                .background(
                    isActive
                    ? Color.accentColor
                    : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
