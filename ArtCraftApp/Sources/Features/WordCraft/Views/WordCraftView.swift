
import SwiftUI

struct WordCraftView: View {

    @State private var selectedTab: WordRibbonTab = .home
    @State private var documentTitle = "Untitled Document"

    @State private var documentText = ""

    @State private var isBold = false
    @State private var isItalic = false
    @State private var isUnderlined = false
    @State private var fontSize: Double = 12

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
                    documentTitle = "Untitled Document"
                    documentText = ""
                } label: {
                    Label("New", systemImage: "doc.badge.plus")
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
                fontSize: $fontSize
            )

            Divider()

            // Document Editor

            ScrollView {
                VStack {
                    TextEditor(text: $documentText)
                        .font(.system(size: fontSize))
                        .frame(minHeight: 650)
                        .padding(24)
                        .background(Color.white)
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .shadow(
                            color: .black.opacity(0.12),
                            radius: 8
                        )
                }
                .frame(maxWidth: 800)
                .frame(maxWidth: .infinity)
                .padding(24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("WordCraft")
        .navigationBarTitleDisplayMode(.inline)
    }
}
