import SwiftUI

struct ContentView: View {
    @State private var selectedModule: OfficeModule?
    @State private var showingHome = true

    var body: some View {
        VStack(spacing: 0) {
            OfficeTitleBar(module: selectedModule)
            OfficeAppTabs(selection: $selectedModule, showingHome: $showingHome)
            Divider()

            Group {
                if showingHome || selectedModule == nil {
                    OfficeHomeView { module in
                        selectedModule = module
                        showingHome = false
                    }
                } else if let selectedModule {
                    ModuleWorkspace(module: selectedModule)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .preferredColorScheme(.light)
    }
}

enum OfficeModule: String, CaseIterable, Identifiable {
    case wordCraft = "WordCraft"
    case gridCraft = "GridCraft"
    case deckCraft = "DeckCraft"
    case pdfCraft = "PdfCraft"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .wordCraft: "doc.text.fill"
        case .gridCraft: "tablecells"
        case .deckCraft: "rectangle.on.rectangle"
        case .pdfCraft: "doc.richtext.fill"
        }
    }
    var color: Color {
        switch self {
        case .wordCraft: Color(red: 0.13, green: 0.36, blue: 0.72)
        case .gridCraft: Color(red: 0.12, green: 0.52, blue: 0.31)
        case .deckCraft: Color(red: 0.78, green: 0.32, blue: 0.15)
        case .pdfCraft: Color(red: 0.73, green: 0.16, blue: 0.20)
        }
    }
    var description: String {
        switch self {
        case .wordCraft: "Create and format documents"
        case .gridCraft: "Work with tables and calculations"
        case .deckCraft: "Build and present slide decks"
        case .pdfCraft: "Read, annotate and organize PDFs"
        }
    }
}

private struct OfficeTitleBar: View {
    let module: OfficeModule?
    private let officeBlue = Color(red: 0.11, green: 0.28, blue: 0.56)

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
            Text("ArtCraft Office")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
            if let module {
                Text("·")
                    .foregroundStyle(.white.opacity(0.65))
                Label(module.rawValue, systemImage: module.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
            }
            Spacer(minLength: 12)
            if module == nil {
                Text("iPad edition")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(officeBlue)
    }
}

private struct OfficeAppTabs: View {
    @Binding var selection: OfficeModule?
    @Binding var showingHome: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                appTab("Home", icon: "house", isSelected: showingHome, color: .blue) {
                    showingHome = true
                    selection = nil
                }
                ForEach(OfficeModule.allCases) { module in
                    appTab(module.rawValue, icon: module.icon,
                           isSelected: !showingHome && selection == module,
                           color: module.color) {
                        selection = module
                        showingHome = false
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 48)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private func appTab(_ title: String, icon: String, isSelected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                HStack(spacing: 7) {
                    Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                    Text(title).font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                }
                .foregroundStyle(isSelected ? color : Color.primary.opacity(0.78))
                Rectangle().fill(isSelected ? color : .clear).frame(height: 3)
            }
            .padding(.horizontal, 15)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct OfficeHomeView: View {
    let openModule: (OfficeModule) -> Void
    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("ARTCRAFT OFFICE").font(.caption.weight(.semibold)).tracking(1.1).foregroundStyle(.secondary)
                    Text("What would you like to create?").font(.largeTitle.bold())
                    Text("Choose an app to start working.").font(.title3).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(OfficeModule.allCases) { module in
                        Button { openModule(module) } label: {
                            HStack(spacing: 16) {
                                Image(systemName: module.icon)
                                    .font(.system(size: 25, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 54, height: 54)
                                    .background(module.color, in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(module.rawValue).font(.headline).foregroundStyle(.primary)
                                    Text(module.description).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct ModuleWorkspace: View {
    let module: OfficeModule

    var body: some View {
        Group {
            switch module {
            case .wordCraft: WordCraftView()
            case .gridCraft: GridCraftView()
            case .deckCraft: DeckCraftView()
            case .pdfCraft: PdfCraftView()
            }
        }
    }
}
