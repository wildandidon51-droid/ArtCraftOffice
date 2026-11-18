import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

private func normalizedJPEG(_ data: Data) -> Data? {
    guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
    let scale = min(1, 2560 / max(image.size.width, image.size.height))
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
        image.draw(in: CGRect(origin: .zero, size: size))
    }.jpegData(compressionQuality: 0.86)
}

private enum DeckShapeKind: String, Codable, CaseIterable, Identifiable {
    case rectangle
    case ellipse
    case arrow
    var id: String { rawValue }
    var title: String {
        switch self { case .rectangle: "Rectangle"; case .ellipse: "Oval"; case .arrow: "Right arrow" }
    }
    var pptxGeometry: String {
        switch self { case .rectangle: "rect"; case .ellipse: "ellipse"; case .arrow: "rightArrow" }
    }
    static func fromPPTX(_ value: String) -> DeckShapeKind? {
        switch value { case "rect": .rectangle; case "ellipse": .ellipse; case "rightArrow": .arrow; default: nil }
    }
}

private struct DeckShape: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: DeckShapeKind
    var text = "Text"
    var x = 0.58
    var y = 0.36
    var width = 0.27
    var height = 0.25
    var fill = "4472C4"
    var uiColor: UIColor {
        let value = UInt32(fill, radix: 16) ?? 0x4472C4
        return UIColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}

private struct DeckShapePath: Shape {
    let kind: DeckShapeKind
    func path(in rect: CGRect) -> Path {
        switch kind {
        case .rectangle: Path(roundedRect: rect, cornerRadius: 4)
        case .ellipse: Path(ellipseIn: rect)
        case .arrow:
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.25))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.25))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.75))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.75))
                path.closeSubpath()
            }
        }
    }
}

private struct DeckShapePreview: View {
    let shape: DeckShape
    var body: some View {
        DeckShapePath(kind: shape.kind)
            .fill(Color(uiColor: shape.uiColor))
            .overlay {
                Text(shape.text)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(4)
                    .minimumScaleFactor(0.5)
            }
    }
}

private struct DeckSlide: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = "New slide"
    var body = "Add your story here."
    var notes = ""
    var imageData: Data? = nil
    var additionalImageData: [Data] = []
    var shapes: [DeckShape] = []

    var images: [Data] { (imageData.map { [$0] } ?? []) + additionalImageData }

    init(id: UUID = UUID(), title: String = "New slide", body: String = "Add your story here.", notes: String = "", images: [Data] = [], shapes: [DeckShape] = []) {
        self.id = id
        self.title = title
        self.body = body
        self.notes = notes
        imageData = images.first
        additionalImageData = Array(images.dropFirst())
        self.shapes = shapes
    }

    private enum CodingKeys: String, CodingKey { case id, title, body, notes, imageData, additionalImageData, shapes }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? "New slide"
        body = try values.decodeIfPresent(String.self, forKey: .body) ?? "Add your story here."
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        imageData = try values.decodeIfPresent(Data.self, forKey: .imageData)
        additionalImageData = try values.decodeIfPresent([Data].self, forKey: .additionalImageData) ?? []
        shapes = try values.decodeIfPresent([DeckShape].self, forKey: .shapes) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(title, forKey: .title)
        try values.encode(body, forKey: .body)
        try values.encode(notes, forKey: .notes)
        try values.encodeIfPresent(imageData, forKey: .imageData)
        try values.encode(additionalImageData, forKey: .additionalImageData)
        try values.encode(shapes, forKey: .shapes)
    }

    mutating func appendImage(_ data: Data) {
        if imageData == nil { imageData = data }
        else { additionalImageData.append(data) }
    }

    mutating func removeLastImage() {
        if !additionalImageData.isEmpty { additionalImageData.removeLast() }
        else { imageData = nil }
    }
}

private struct DeckPresentationView: View {
    let slides: [DeckSlide]
    let theme: DeckTheme
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var showingNotes = false

    init(slides: [DeckSlide], theme: DeckTheme, initialIndex: Int) {
        self.slides = slides
        self.theme = theme
        _index = State(initialValue: min(max(initialIndex, 0), max(slides.count - 1, 0)))
    }

    private var hasSlides: Bool { slides.indices.contains(index) }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    Label("ArtCraft Slide Show", systemImage: "play.rectangle.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if hasSlides {
                        Text("\(index + 1) of \(slides.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color(uiColor: theme.foreground).opacity(0.68))
                        Button { showingNotes.toggle() } label: {
                            Label(showingNotes ? "Hide notes" : "Show notes", systemImage: "text.alignleft")
                        }
                        .buttonStyle(.bordered)
                    }
                    Button("End show", systemImage: "xmark", role: .cancel) { dismiss() }
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)

                Spacer(minLength: 12)
                if hasSlides {
                    slideCanvas(width: min(geometry.size.width - 48, 1440))
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 24)
                } else {
                    ContentUnavailableView("No slides", systemImage: "rectangle.on.rectangle")
                }
                if showingNotes, hasSlides {
                    HStack(alignment: .top, spacing: 10) {
                        Label("Presenter notes", systemImage: "text.alignleft")
                            .font(.caption.weight(.semibold))
                            .frame(width: 125, alignment: .leading)
                        ScrollView {
                            Text(slides[index].notes.isEmpty ? "No notes for this slide." : slides[index].notes)
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 92)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color(uiColor: theme.foreground).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 24)
                }
                Spacer(minLength: 12)

                HStack(spacing: 20) {
                    Button { move(by: -1) } label: { Label("Previous", systemImage: "chevron.left") }
                        .disabled(index == 0 || !hasSlides)
                    Spacer()
                    Text("Tap Next or use the arrow keys")
                        .font(.caption).foregroundStyle(Color(uiColor: theme.foreground).opacity(0.65))
                    Spacer()
                    Button { move(by: 1) } label: { Label("Next", systemImage: "chevron.right") }
                        .disabled(index >= slides.count - 1 || !hasSlides)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 18).padding(.vertical, 12)
            }
            .foregroundStyle(Color(uiColor: theme.foreground))
            .background(Color(uiColor: theme.background).ignoresSafeArea())
        }
        .onKeyPress(.leftArrow) { move(by: -1); return .handled }
        .onKeyPress(.rightArrow) { move(by: 1); return .handled }
        .statusBarHidden()
    }

    private func slideCanvas(width: CGFloat) -> some View {
        GeometryReader { proxy in
            let slide = slides[index]
            let titleSize = min(max(proxy.size.width * 0.052, 28), 68)
            let bodySize = min(max(proxy.size.width * 0.03, 20), 38)
            VStack(alignment: .leading, spacing: proxy.size.height * 0.06) {
                Text(slide.title.isEmpty ? "Untitled slide" : slide.title)
                    .font(.system(size: titleSize, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 24) {
                    ScrollView {
                        Text(slide.body)
                            .font(.system(size: bodySize, weight: .regular, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !slide.images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(slide.images.enumerated()), id: \.offset) { _, data in
                                    if let image = UIImage(data: data) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxWidth: proxy.size.width * 0.34, maxHeight: proxy.size.height * 0.52)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, proxy.size.width * 0.08)
            .padding(.vertical, proxy.size.height * 0.11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(uiColor: theme.background), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                GeometryReader { geometry in
                    ForEach(slide.shapes) { shape in
                        DeckShapePreview(shape: shape)
                            .frame(width: geometry.size.width * CGFloat(shape.width), height: geometry.size.height * CGFloat(shape.height))
                            .position(x: geometry.size.width * CGFloat(shape.x + shape.width / 2), y: geometry.size.height * CGFloat(shape.y + shape.height / 2))
                    }
                }
            }
            .shadow(color: .black.opacity(0.2), radius: 16, y: 7)
        }
        .frame(maxWidth: width)
    }

    private func move(by amount: Int) {
        index = min(max(index + amount, 0), max(slides.count - 1, 0))
    }
}

private enum DeckTheme: String, Codable, CaseIterable, Identifiable {
    case midnight = "Midnight"
    case paper = "Paper"
    case ocean = "Ocean"
    var id: String { rawValue }
    var background: UIColor {
        switch self {
        case .midnight: UIColor(red: 0.08, green: 0.11, blue: 0.2, alpha: 1)
        case .paper: UIColor(red: 0.98, green: 0.97, blue: 0.93, alpha: 1)
        case .ocean: UIColor(red: 0.02, green: 0.32, blue: 0.42, alpha: 1)
        }
    }
    var foreground: UIColor { self == .paper ? .darkText : .white }
    var swiftUIColor: Color { Color(uiColor: background) }
}

private struct DeckDocument: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = "Untitled Presentation"
    var slides = [DeckSlide(title: "Welcome", body: "Make your first slide.")]
    var theme: DeckTheme = .midnight
}

struct DeckCraftView: View {
    @State private var deck: DeckDocument
    @State private var savedDecks: [DeckDocument]
    @State private var selectedID: UUID?
    @State private var exportURL: URL?
    @State private var showingImporter = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedShapeID: UUID?
    @State private var statusMessage = ""
    @State private var showingNotes = false
    @State private var isPresenting = false
    @State private var pendingSave: Task<Void, Never>?

    init() {
        if let saved = Self.loadLibrary() {
            let current = saved.first ?? DeckDocument()
            _savedDecks = State(initialValue: saved)
            _deck = State(initialValue: current)
            _selectedID = State(initialValue: current.slides.first?.id)
        } else if let data = UserDefaults.standard.data(forKey: "artcraft.deckcraft.library.v1"),
                  let saved = try? JSONDecoder().decode([DeckDocument].self, from: data) {
            let current = saved.first ?? DeckDocument()
            _savedDecks = State(initialValue: saved)
            _deck = State(initialValue: current)
            _selectedID = State(initialValue: current.slides.first?.id)
        } else if let data = UserDefaults.standard.data(forKey: "artcraft.deckcraft.document.v1"),
                  let legacy = try? JSONDecoder().decode(DeckDocument.self, from: data) {
            _savedDecks = State(initialValue: [legacy])
            _deck = State(initialValue: legacy)
            _selectedID = State(initialValue: legacy.slides.first?.id)
        } else {
            let fresh = DeckDocument()
            _savedDecks = State(initialValue: [])
            _deck = State(initialValue: fresh)
            _selectedID = State(initialValue: fresh.slides.first?.id)
        }
    }

    private var selectedIndex: Int { deck.slides.firstIndex(where: { $0.id == selectedID }) ?? 0 }
    private var hasSelectedSlide: Bool { !deck.slides.isEmpty && deck.slides.indices.contains(selectedIndex) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                slideRail
                Divider()
                editor
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onChange(of: deck) { _, updated in scheduleSave(updated) }
        .onDisappear {
            pendingSave?.cancel()
            persist(deck)
        }
        .fullScreenCover(isPresented: $isPresenting) {
            DeckPresentationView(slides: deck.slides, theme: deck.theme, initialIndex: selectedIndex)
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [UTType(filenameExtension: "pptx") ?? .data], allowsMultipleSelection: false) { result in
            importPPTX(result)
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { @MainActor in await insertPhoto(item) }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            TextField("Presentation title", text: $deck.title)
                .font(.headline).textFieldStyle(.plain).frame(maxWidth: 260)
            if !statusMessage.isEmpty {
                Text(statusMessage).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Menu {
                ForEach(DeckTheme.allCases) { theme in
                    Button(theme.rawValue) { deck.theme = theme }
                }
            } label: { Label(deck.theme.rawValue, systemImage: "paintpalette") }
            .buttonStyle(.bordered)
                Menu {
                    ForEach(DeckShapeKind.allCases) { kind in
                        Button(kind.title, systemImage: kind == .ellipse ? "circle" : (kind == .arrow ? "arrow.right" : "square")) { addShape(kind) }
                    }
                } label: { Label("Shapes", systemImage: "scribble.variable") }
                    .buttonStyle(.bordered)
            Button { addSlide() } label: { Label("New slide", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
            Button { isPresenting = true } label: { Label("Present", systemImage: "play.fill") }
                .buttonStyle(.bordered)
                .disabled(deck.slides.isEmpty)
            Menu {
                Button("Open PowerPoint (.pptx)", systemImage: "folder", action: { showingImporter = true })
                Button("New presentation", systemImage: "doc.badge.plus", action: newDeck)
                Divider()
                Button("Duplicate slide", systemImage: "plus.square.on.square", action: duplicateSlide)
                    .disabled(!hasSelectedSlide)
                Button("Move up", systemImage: "arrow.up", action: { moveSlide(by: -1) })
                    .disabled(selectedIndex == 0 || !hasSelectedSlide)
                Button("Move down", systemImage: "arrow.down", action: { moveSlide(by: 1) })
                    .disabled(selectedIndex >= deck.slides.count - 1 || !hasSelectedSlide)
                Button("Delete slide", systemImage: "trash", role: .destructive, action: deleteSlide)
                    .disabled(!hasSelectedSlide)
                Divider()
                if !savedDecks.isEmpty {
                    Menu("Open saved presentation") {
                        ForEach(savedDecks) { saved in
                            Button(saved.title) { openDeck(saved.id) }
                        }
                    }
                }
                Button("Export PDF", systemImage: "doc.richtext", action: exportPDF)
                Button("Export PowerPoint (.pptx)", systemImage: "play.rectangle", action: exportPPTX)
                if let exportURL { ShareLink(item: exportURL) { Label("Share last export", systemImage: "square.and.arrow.up") } }
            } label: { Label("File", systemImage: "ellipsis.circle") }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(.bar)
    }

    private var slideRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SLIDES").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
                Spacer()
                Text("\(deck.slides.count)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }.padding(.horizontal, 14).padding(.top, 14)
            List {
                ForEach(deck.slides) { slide in
                    let index = deck.slides.firstIndex(where: { $0.id == slide.id }) ?? 0
                    Button { selectedID = slide.id; selectedShapeID = nil } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 6).fill(deck.theme.swiftUIColor)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(slide.title.isEmpty ? "Untitled" : slide.title)
                                        .font(.system(size: 8, weight: .bold)).lineLimit(1)
                                    Text(slide.body).font(.system(size: 6)).lineLimit(2).opacity(0.8)
                                }.foregroundStyle(Color(uiColor: deck.theme.foreground)).padding(8)
                                GeometryReader { geometry in
                                    ForEach(slide.shapes) { shape in
                                        DeckShapePreview(shape: shape)
                                            .frame(width: geometry.size.width * CGFloat(shape.width), height: geometry.size.height * CGFloat(shape.height))
                                            .position(x: geometry.size.width * CGFloat(shape.x + shape.width / 2), y: geometry.size.height * CGFloat(shape.y + shape.height / 2))
                                    }
                                }
                            }
                            .aspectRatio(16 / 9, contentMode: .fit)
                            HStack {
                                Text("\(index + 1)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                Text(slide.title.isEmpty ? "Untitled slide" : slide.title).font(.caption).lineLimit(1)
                            }
                        }
                        .padding(7)
                        .background(selectedID == slide.id ? Color.accentColor.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
        .frame(width: 220)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private var editor: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 12)
            if hasSelectedSlide {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("Slide title", text: slideBinding(\.title))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .textFieldStyle(.plain)
                        .foregroundStyle(Color(uiColor: deck.theme.foreground))
                    TextEditor(text: slideBinding(\.body))
                        .font(.system(size: 22, weight: .regular, design: .rounded))
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(Color(uiColor: deck.theme.foreground))
                        .frame(minHeight: 170)
                        .overlay(alignment: .topLeading) {
                            if deck.slides[selectedIndex].body.isEmpty {
                                Text("Add your content").font(.title2).foregroundStyle(Color(uiColor: deck.theme.foreground).opacity(0.45)).padding(.top, 8).allowsHitTesting(false)
                            }
                        }
                    if !deck.slides[selectedIndex].images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(deck.slides[selectedIndex].images.enumerated()), id: \.offset) { _, data in
                                    if let image = UIImage(data: data) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxHeight: 180)
                                    }
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(36)
                .frame(maxWidth: 820, maxHeight: .infinity, alignment: .topLeading)
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(Color(uiColor: deck.theme.background), in: RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                .overlay {
                    GeometryReader { geometry in
                        ForEach(deck.slides[selectedIndex].shapes) { shape in
                            Button { selectedShapeID = shape.id } label: {
                                DeckShapePreview(shape: shape)
                                    .overlay {
                                        if selectedShapeID == shape.id {
                                            DeckShapePath(kind: shape.kind).stroke(Color.white, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                                        }
                                    }
                                    .frame(width: geometry.size.width * CGFloat(shape.width), height: geometry.size.height * CGFloat(shape.height))
                            }
                            .buttonStyle(.plain)
                            .position(x: geometry.size.width * CGFloat(shape.x + shape.width / 2), y: geometry.size.height * CGFloat(shape.y + shape.height / 2))
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Text("\(selectedIndex + 1) / \(deck.slides.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color(uiColor: deck.theme.foreground).opacity(0.55))
                        .padding(14)
                }
                .padding(.horizontal, 24)
                if let shapeID = selectedShapeID,
                   deck.slides[selectedIndex].shapes.contains(where: { $0.id == shapeID }) {
                    HStack(spacing: 8) {
                        TextField("Shape text", text: shapeBinding(shapeID)).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                        Menu {
                            Button("Blue") { setShapeFill(shapeID, color: "4472C4") }
                            Button("Red") { setShapeFill(shapeID, color: "C0504D") }
                            Button("Green") { setShapeFill(shapeID, color: "70AD47") }
                            Button("Orange") { setShapeFill(shapeID, color: "ED7D31") }
                            Button("Purple") { setShapeFill(shapeID, color: "8064A2") }
                        } label: { Label("Fill", systemImage: "paintbucket") }.buttonStyle(.bordered)
                        Button { moveShape(shapeID, dx: -0.025, dy: 0) } label: { Image(systemName: "arrow.left") }.buttonStyle(.bordered)
                        Button { moveShape(shapeID, dx: 0.025, dy: 0) } label: { Image(systemName: "arrow.right") }.buttonStyle(.bordered)
                        Button { moveShape(shapeID, dx: 0, dy: -0.025) } label: { Image(systemName: "arrow.up") }.buttonStyle(.bordered)
                        Button { moveShape(shapeID, dx: 0, dy: 0.025) } label: { Image(systemName: "arrow.down") }.buttonStyle(.bordered)
                        Button("Delete shape", systemImage: "trash", role: .destructive) { deleteShape(shapeID) }.buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 24)
                }
                HStack {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Add picture", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)
                    if !deck.slides[selectedIndex].images.isEmpty {
                        Button("Remove last picture", systemImage: "trash", role: .destructive) {
                            deck.slides[selectedIndex].removeLastImage()
                        }
                        .buttonStyle(.bordered)
                    }
                    Text("\(deck.slides[selectedIndex].images.count)/4 pictures")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 24)
                HStack {
                    Button { showingNotes.toggle() } label: {
                        Label(showingNotes ? "Hide notes" : "Speaker notes", systemImage: "text.alignleft")
                    }.buttonStyle(.bordered)
                    Spacer()
                    Text("\(deck.slides.count) slides").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                if showingNotes {
                    TextField("Speaker notes", text: slideBinding(\.notes), axis: .vertical)
                        .lineLimit(2...5).textFieldStyle(.roundedBorder).padding(.horizontal, 24)
                }
            } else {
                ContentUnavailableView("No slides", systemImage: "rectangle.on.rectangle", description: Text("Create a slide to start your presentation."))
            }
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func slideBinding(_ keyPath: WritableKeyPath<DeckSlide, String>) -> Binding<String> {
        Binding(
            get: { hasSelectedSlide ? deck.slides[selectedIndex][keyPath: keyPath] : "" },
            set: { value in if hasSelectedSlide { deck.slides[selectedIndex][keyPath: keyPath] = value } }
        )
    }

    private func shapeBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { hasSelectedSlide ? deck.slides[selectedIndex].shapes.first(where: { $0.id == id })?.text ?? "" : "" },
            set: { value in
                guard hasSelectedSlide, let index = deck.slides[selectedIndex].shapes.firstIndex(where: { $0.id == id }) else { return }
                deck.slides[selectedIndex].shapes[index].text = value
                exportURL = nil
            }
        )
    }

    private func addShape(_ kind: DeckShapeKind) {
        guard hasSelectedSlide else { return }
        let shape = DeckShape(kind: kind)
        deck.slides[selectedIndex].shapes.append(shape)
        selectedShapeID = shape.id
        exportURL = nil
        statusMessage = "\(kind.title) added"
    }

    private func setShapeFill(_ id: UUID, color: String) {
        guard hasSelectedSlide, let index = deck.slides[selectedIndex].shapes.firstIndex(where: { $0.id == id }) else { return }
        deck.slides[selectedIndex].shapes[index].fill = color
        exportURL = nil
    }

    private func moveShape(_ id: UUID, dx: Double, dy: Double) {
        guard hasSelectedSlide, let index = deck.slides[selectedIndex].shapes.firstIndex(where: { $0.id == id }) else { return }
        var shape = deck.slides[selectedIndex].shapes[index]
        shape.x = min(max(shape.x + dx, 0), 1 - shape.width)
        shape.y = min(max(shape.y + dy, 0), 1 - shape.height)
        deck.slides[selectedIndex].shapes[index] = shape
        exportURL = nil
    }

    private func deleteShape(_ id: UUID) {
        guard hasSelectedSlide else { return }
        deck.slides[selectedIndex].shapes.removeAll { $0.id == id }
        selectedShapeID = nil
        exportURL = nil
    }

    private func addSlide() {
        let slide = DeckSlide()
        deck.slides.append(slide)
        selectedID = slide.id
    }

    private func duplicateSlide() {
        guard hasSelectedSlide else { return }
        var copy = deck.slides[selectedIndex]
        copy.id = UUID()
        copy.title += " copy"
        deck.slides.insert(copy, at: selectedIndex + 1)
        selectedID = copy.id
    }

    private func deleteSlide() {
        guard hasSelectedSlide else { return }
        deck.slides.remove(at: selectedIndex)
        selectedID = deck.slides.indices.contains(selectedIndex) ? deck.slides[selectedIndex].id : deck.slides.last?.id
    }

    private func moveSlide(by offset: Int) {
        let destination = selectedIndex + offset
        guard deck.slides.indices.contains(selectedIndex), deck.slides.indices.contains(destination) else { return }
        deck.slides.swapAt(selectedIndex, destination)
    }

    private func newDeck() {
        deck = DeckDocument()
        selectedID = deck.slides.first?.id
        exportURL = nil
        persist(deck)
    }

    private func persist(_ updated: DeckDocument) {
        if let index = savedDecks.firstIndex(where: { $0.id == updated.id }) {
            savedDecks[index] = updated
        } else {
            savedDecks.insert(updated, at: 0)
        }
        do {
            try FileManager.default.createDirectory(at: Self.libraryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(savedDecks)
            try data.write(to: Self.libraryURL, options: .atomic)
        } catch { }
    }

    private func scheduleSave(_ updated: DeckDocument) {
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            persist(updated)
        }
    }

    private func openDeck(_ id: UUID) {
        guard let saved = savedDecks.first(where: { $0.id == id }) else { return }
        deck = saved
        selectedID = saved.slides.first?.id
        selectedShapeID = nil
        exportURL = nil
    }

    private func exportPDF() {
        let bounds = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let data = renderer.pdfData { context in
            for slide in deck.slides {
                context.beginPage()
                deck.theme.background.setFill()
                context.fill(bounds)
                let color = deck.theme.foreground
                let titleAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 54, weight: .bold), .foregroundColor: color]
                let bodyAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 30), .foregroundColor: color.withAlphaComponent(0.9)]
                (slide.title as NSString).draw(in: CGRect(x: 96, y: 86, width: 1088, height: 120), withAttributes: titleAttributes)
                let hasImage = !slide.images.isEmpty
                (slide.body as NSString).draw(in: CGRect(x: 104, y: 250, width: hasImage ? 550 : 1050, height: 380), withAttributes: bodyAttributes)
                for (index, imageData) in slide.images.enumerated() {
                    guard let image = UIImage(data: imageData) else { continue }
                    let rowCount = max(1, (slide.images.count + 1) / 2)
                    let rowHeight = min(190, 390 / CGFloat(rowCount))
                    let imageBounds = slide.images.count == 1
                        ? CGRect(x: 710, y: 230, width: 470, height: 410)
                        : CGRect(x: 690 + CGFloat(index % 2) * 240, y: 230 + CGFloat(index / 2) * (410 / CGFloat(rowCount)), width: 220, height: rowHeight)
                    let scale = min(imageBounds.width / image.size.width, imageBounds.height / image.size.height)
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    image.draw(in: CGRect(x: imageBounds.midX - size.width / 2, y: imageBounds.midY - size.height / 2, width: size.width, height: size.height))
                }
                for shape in slide.shapes {
                    let shapeBounds = CGRect(x: CGFloat(shape.x) * bounds.width, y: CGFloat(shape.y) * bounds.height,
                                             width: CGFloat(shape.width) * bounds.width, height: CGFloat(shape.height) * bounds.height)
                    let path = DeckShapePath(kind: shape.kind).path(in: shapeBounds)
                    shape.uiColor.setFill()
                    UIBezierPath(cgPath: path.cgPath).fill()
                    let textAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: max(14, shapeBounds.height * 0.12), weight: .semibold), .foregroundColor: UIColor.white]
                    (shape.text as NSString).draw(in: shapeBounds.insetBy(dx: 10, dy: 8), withAttributes: textAttributes)
                }
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeFileName(deck.title) + ".pdf")
        do {
            try data.write(to: url, options: .atomic)
            exportURL = url
            statusMessage = "PDF ready to share"
        } catch {
            exportURL = nil
            statusMessage = "Could not export PDF"
        }
    }

    private func exportPPTX() {
        let slides = deck.slides.map { slide in
            let shapes = slide.shapes.map {
                DeckPptxShape(kind: $0.kind.pptxGeometry, text: $0.text, x: $0.x, y: $0.y, width: $0.width, height: $0.height, fill: $0.fill)
            }
            return DeckPptxSlide(title: slide.title, body: slide.body, notes: slide.notes, images: slide.images, shapes: shapes)
        }
        do {
            let data = try DeckPptxCodec.encode(title: deck.title, slides: slides, theme: deck.theme.rawValue)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeFileName(deck.title) + ".pptx")
            try data.write(to: url, options: .atomic)
            exportURL = url
            statusMessage = "PowerPoint file ready to share"
        } catch {
            exportURL = nil
            statusMessage = "Could not export this PowerPoint file"
        }
    }

    @MainActor
    private func insertPhoto(_ item: PhotosPickerItem) async {
        defer { selectedPhoto = nil }
        guard hasSelectedSlide, deck.slides[selectedIndex].images.count < 4 else {
            statusMessage = "A slide can contain up to four pictures"
            return
        }
        guard hasSelectedSlide,
              let data = try? await item.loadTransferable(type: Data.self),
              let jpeg = normalizedJPEG(data) else {
            statusMessage = "Could not load this picture"
            return
        }
        deck.slides[selectedIndex].appendImage(jpeg)
        exportURL = nil
        statusMessage = "Picture added to slide"
    }

    private func importPPTX(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let content = try DeckPptxCodec.decode(Data(contentsOf: url))
            let slides = content.slides.map { slide in
                let shapes = slide.shapes.compactMap { source -> DeckShape? in
                    guard let kind = DeckShapeKind.fromPPTX(source.kind) else { return nil }
                    return DeckShape(kind: kind, text: source.text, x: source.x, y: source.y, width: source.width, height: source.height, fill: source.fill)
                }
                return DeckSlide(title: slide.title, body: slide.body, notes: slide.notes, images: slide.images.compactMap(normalizedJPEG), shapes: shapes)
            }
            let titleCandidate = content.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let importedTitle = titleCandidate.flatMap { $0.isEmpty ? nil : $0 }
                ?? url.deletingPathExtension().lastPathComponent
            deck = DeckDocument(title: importedTitle,
                                slides: slides,
                                theme: DeckTheme(rawValue: content.theme) ?? .midnight)
            selectedID = deck.slides.first?.id
            selectedShapeID = nil
            exportURL = nil
            statusMessage = "PowerPoint file opened"
            persist(deck)
        } catch {
            statusMessage = "Could not open this PowerPoint file"
        }
    }

    private static var libraryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ArtCraftOffice/DeckCraft/library.json")
    }

    private static func loadLibrary() -> [DeckDocument]? {
        guard let data = try? Data(contentsOf: libraryURL) else { return nil }
        return try? JSONDecoder().decode([DeckDocument].self, from: data)
    }
}
