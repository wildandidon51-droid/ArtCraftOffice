
import SwiftUI

// MARK: - Dashboard

struct ContentView: View {

    @State private var selectedModule: OfficeModule?

    private let columns = [
        GridItem(.adaptive(minimum: 240), spacing: 20)
    ]

    private let modules = OfficeModule.allCases

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome to")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        Text("ArtCraft Office")
                            .font(.largeTitle.bold())

                        Text("Everything you need to create and work.")
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(modules) { module in
                            ModuleCard(module: module) {
                                selectedModule = module
                            }
                        }
                    }
                }
                .padding(28)
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "person.crop.circle")
                        .font(.title2)
                }
            }
        }
        .sheet(item: $selectedModule) { module in
            ModuleDetailView(module: module)
        }
    }
}

// MARK: - Office Modules

enum OfficeModule: String, CaseIterable, Identifiable {

    case wordCraft = "WordCraft"
    case gridCraft = "GridCraft"
    case deckCraft = "DeckCraft"
    case pdfCraft = "PdfCraft"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .wordCraft:
            return "Create and edit documents"
        case .gridCraft:
            return "Organize data and spreadsheets"
        case .deckCraft:
            return "Create beautiful presentations"
        case .pdfCraft:
            return "Read and manage PDF files"
        }
    }

    var icon: String {
        switch self {
        case .wordCraft: return "doc.text"
        case .gridCraft: return "tablecells"
        case .deckCraft: return "rectangle.on.rectangle"
        case .pdfCraft: return "doc.richtext"
        }
    }

    var color: Color {
        switch self {
        case .wordCraft: return .blue
        case .gridCraft: return .green
        case .deckCraft: return .orange
        case .pdfCraft: return .red
        }
    }
}

// MARK: - Module Card

struct ModuleCard: View {

    let module: OfficeModule
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {

                Image(systemName: module.icon)
                    .font(.system(size: 32))
                    .foregroundStyle(module.color)

                Text(module.rawValue)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)

                Text(module.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                HStack {
                    Text("IN DEVELOPMENT")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(module.color)

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 180)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Module Detail

struct ModuleDetailView: View {

    let module: OfficeModule

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if module == .wordCraft {
                    WordCraftView()
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: module.icon)
                            .font(.system(size: 52))
                            .foregroundStyle(module.color)

                        Text(module.rawValue)
                            .font(.largeTitle.bold())

                        Text("This module is under development.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
