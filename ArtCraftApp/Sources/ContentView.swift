
import SwiftUI

@main
struct ArtCraftOfficeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {

    private let columns = [
        GridItem(.adaptive(minimum: 240), spacing: 20)
    ]

    private let modules: [OfficeModule] = [
        OfficeModule(
            name: "WordCraft",
            description: "Create and edit documents",
            icon: "doc.text",
            color: .blue
        ),
        OfficeModule(
            name: "GridCraft",
            description: "Organize data and spreadsheets",
            icon: "tablecells",
            color: .green
        ),
        OfficeModule(
            name: "DeckCraft",
            description: "Create beautiful presentations",
            icon: "rectangle.on.rectangle",
            color: .orange
        ),
        OfficeModule(
            name: "PdfCraft",
            description: "Read and manage PDF files",
            icon: "doc.richtext",
            color: .red
        )
    ]

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
                            ModuleCard(module: module)
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
    }
}

struct OfficeModule: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let icon: String
    let color: Color
}

struct ModuleCard: View {
    let module: OfficeModule

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: module.icon)
                .font(.system(size: 32))
                .foregroundStyle(module.color)

            Text(module.name)
                .font(.title2.bold())

            Text(module.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            HStack {
                Text("Coming Soon")
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
    }
}
