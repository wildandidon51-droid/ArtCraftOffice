import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import CryptoKit
import Vision
import CoreText

private let pdfRedactionAuthor = "ArtCraftOffice.Redaction"

private struct PDFOCRLine: Identifiable {
    let id = UUID()
    let pageIndex: Int
    let text: String
    let bounds: CGRect
}

private enum PdfTextPrompt: Equatable {
    case note
    case signature
    var title: String { self == .note ? "Add note to page" : "Add typed signature" }
    var placeholder: String { self == .note ? "Note" : "Type your name" }
    var message: String { self == .note ? "The note will be added to page." : "This adds a visible signature annotation to the current page." }
    var actionTitle: String { self == .note ? "Add note" : "Add signature" }
}

struct PdfCraftView: View {
    @State private var showingImporter = false
    @State private var mergeNextImport = false
    @State private var pdfDocument: PDFDocument?
    @State private var pdfView: PDFView?
    @State private var fileName = ""
    @State private var searchText = ""
    @State private var searchResults: [PDFSelection] = []
    @State private var searchIndex = 0
    @State private var pageInput = "1"
    @State private var bookmarkedPages: [Int] = []
    @State private var bookmarkIdentity = ""
    @State private var exportURL: URL?
    @State private var displayMode: PDFDisplayMode = .singlePageContinuous
    @State private var statusMessage: String?
    @State private var showingPageList = true
    @State private var textPrompt: PdfTextPrompt?
    @State private var noteText = ""
    @State private var signatureText = ""
    @State private var showingProtectSheet = false
    @State private var ownerPassword = ""
    @State private var userPassword = ""
    @State private var allowPrinting = true
    @State private var allowCopying = true
    @State private var allowAnnotations = true
    @State private var allowPageAssembly = true
    @State private var showingUnlockPrompt = false
    @State private var unlockPassword = ""
    @State private var showingSplitSheet = false
    @State private var showingFormFields = false
    @State private var splitStartPage = "1"
    @State private var splitEndPage = "1"
    @State private var showingOCRSheet = false
    @State private var isRecognizingOCR = false
    @State private var ocrLines: [PDFOCRLine] = []
    @State private var ocrSearchText = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if pdfDocument != nil {
                searchBar
                Divider()
            }
            HStack(spacing: 0) {
                if let pdfView, showingPageList {
                    PDFThumbnailRail(pdfView: pdfView)
                        .frame(width: 150)
                    Divider()
                }
                if let pdfDocument {
                    PDFDocumentSurface(document: pdfDocument, displayMode: displayMode) { view in
                        if pdfView !== view { pdfView = view }
                    }
                } else {
                    ContentUnavailableView("Open a PDF", systemImage: "doc.richtext", description: Text(statusMessage ?? "Read, search, annotate and organize PDF pages."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if pdfDocument != nil {
                Divider()
                statusBar
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: mergeNextImport) { result in
            importPDFs(result)
        }
        .alert(textPrompt?.title ?? "Annotation", isPresented: Binding(
            get: { textPrompt != nil },
            set: { if !$0 { textPrompt = nil } }
        )) {
            TextField(textPrompt?.placeholder ?? "", text: textPrompt == .signature ? $signatureText : $noteText)
            Button(textPrompt?.actionTitle ?? "Add", action: submitTextPrompt)
            Button("Cancel", role: .cancel) {
                noteText = ""
                signatureText = ""
                textPrompt = nil
            }
        } message: {
            Text(textPrompt?.message ?? "")
        }
        .sheet(isPresented: $showingProtectSheet) {
            NavigationStack {
                Form {
                    Section("Passwords") {
                        SecureField("Owner password (required)", text: $ownerPassword)
                        SecureField("Open password (optional)", text: $userPassword)
                    }
                    Section("Allowed actions") {
                        Toggle("Print", isOn: $allowPrinting)
                        Toggle("Copy content", isOn: $allowCopying)
                        Toggle("Add comments and fill forms", isOn: $allowAnnotations)
                        Toggle("Organize pages", isOn: $allowPageAssembly)
                    }
                    Section {
                        Button("Create protected PDF", systemImage: "lock.doc", action: exportProtectedPDF)
                            .disabled(ownerPassword.count < 6)
                    } footer: {
                        Text("Use at least 6 characters for the owner password. The protected copy will be shared from this device.")
                    }
                }
                .navigationTitle("Protect PDF")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showingProtectSheet = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingUnlockPrompt) {
            NavigationStack {
                Form {
                    Section("This PDF is password-protected") {
                        SecureField("Password", text: $unlockPassword)
                        Button("Unlock", systemImage: "lock.open", action: unlockDocument)
                            .disabled(unlockPassword.isEmpty)
                    }
                    if let statusMessage {
                        Section { Text(statusMessage).foregroundStyle(.secondary) }
                    }
                }
                .navigationTitle("Unlock PDF")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showingUnlockPrompt = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingSplitSheet) {
            NavigationStack {
                Form {
                    Section("Pages to export") {
                        TextField("First page", text: $splitStartPage).keyboardType(.numberPad)
                        TextField("Last page", text: $splitEndPage).keyboardType(.numberPad)
                    }
                    Section {
                        Button("Create PDF", systemImage: "doc.badge.arrow.up", action: exportPageRange)
                    } footer: {
                        Text("Choose an inclusive page range from 1 to \(pdfDocument?.pageCount ?? 0).")
                    }
                }
                .navigationTitle("Export page range")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showingSplitSheet = false } } }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingFormFields) {
            NavigationStack {
                Form {
                    if formFields.isEmpty {
                        ContentUnavailableView("No editable form fields", systemImage: "square.and.pencil", description: Text("This PDF has no text, choice, or checkbox fields that PdfCraft can fill."))
                    } else {
                        ForEach(Array(formFields.enumerated()), id: \.offset) { index, item in
                            Section("\(formFieldTitle(item.annotation, index: index)) · Page \(item.pageNumber)") {
                                if item.annotation.widgetFieldType == .button,
                                   item.annotation.widgetControlType == .checkBoxControl {
                                    Toggle("Checked", isOn: checkboxBinding(item.annotation))
                                } else if let choices = item.annotation.choices, !choices.isEmpty {
                                    Picker("Value", selection: formFieldBinding(item.annotation)) {
                                        Text("Choose…").tag("")
                                        ForEach(choices, id: \.self) { choice in Text(choice).tag(choice) }
                                    }
                                } else {
                                    TextField("Enter value", text: formFieldBinding(item.annotation), axis: item.annotation.isMultiline ? .vertical : .horizontal)
                                        .lineLimit(item.annotation.isMultiline ? 3...6 : 1...1)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Fill PDF form")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showingFormFields = false } } }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingOCRSheet) {
            NavigationStack {
                List {
                    Section("Search recognized text") {
                        TextField("Search OCR text", text: $ocrSearchText)
                            .textInputAutocapitalization(.never)
                    }
                    if filteredOCRLines.isEmpty {
                        ContentUnavailableView("No OCR matches", systemImage: "text.viewfinder", description: Text(ocrLines.isEmpty ? "Run OCR on this PDF to extract text from scanned pages." : "Try another search phrase."))
                    } else {
                        ForEach(filteredOCRLines) { line in
                            HStack(alignment: .top, spacing: 12) {
                                Button {
                                    goToPage(line.pageIndex + 1)
                                    showingOCRSheet = false
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(line.text).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                                        Text("Page \(line.pageIndex + 1)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                Spacer(minLength: 0)
                                Button {
                                    addRedactionMark(onPage: line.pageIndex, bounds: line.bounds)
                                    showingOCRSheet = false
                                } label: {
                                    Image(systemName: "eye.slash.fill")
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Mark OCR line for redaction")
                            }
                        }
                    }
                }
                .navigationTitle("Recognized text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showingOCRSheet = false } } }
            }
            .presentationDetents([.medium, .large])
        }
        .onReceive(NotificationCenter.default.publisher(for: .PDFViewPageChanged)) { notification in
            guard let changedView = notification.object as? PDFView,
                  changedView === pdfView,
                  let page = changedView.currentPage,
                  let pdfDocument else { return }
            pageInput = String(pdfDocument.index(for: page) + 1)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { showingPageList.toggle() } label: { Image(systemName: "sidebar.left") }
                .help("Show or hide page thumbnails")
                .disabled(pdfDocument == nil)
            Text(fileName.isEmpty ? "PdfCraft" : fileName)
                .font(.headline).lineLimit(1).frame(maxWidth: 300, alignment: .leading)
            Spacer(minLength: 4)
            Menu {
                Button("Open PDF", systemImage: "folder") { beginImport(merge: false) }
                    .disabled(isRecognizingOCR)
                Button("Merge PDFs", systemImage: "doc.on.doc") { beginImport(merge: true) }
                    .disabled(isRecognizingOCR)
                Divider()
                Button("Export current PDF", systemImage: "square.and.arrow.up", action: exportPDF)
                    .disabled(pdfDocument == nil)
                Button(isRecognizingOCR ? "Recognizing text…" : "Recognize text with OCR", systemImage: "text.viewfinder", action: recognizeText)
                    .disabled(pdfDocument == nil || isRecognizingOCR)
                Button("Export searchable OCR PDF", systemImage: "doc.text.magnifyingglass", action: exportSearchableOCRPDF)
                    .disabled(ocrLines.isEmpty || redactionCount > 0)
                Button("Export flattened copy", systemImage: "doc.zipper", action: exportFlattenedPDF)
                    .disabled(pdfDocument == nil)
                Button("Export redacted copy", systemImage: "eye.slash", action: exportRedactedPDF)
                    .disabled(redactionCount == 0)
                Button("Export current page", systemImage: "doc", action: exportCurrentPage)
                    .disabled(!(pdfDocument?.allowsDocumentAssembly ?? false))
                Button("Export page range", systemImage: "rectangle.split.2x1") { showingSplitSheet = true }
                    .disabled(!(pdfDocument?.allowsDocumentAssembly ?? false))
                Button("Fill PDF form", systemImage: "square.and.pencil") { showingFormFields = true }
                    .disabled(formFields.isEmpty || !(pdfDocument?.allowsCommenting ?? false))
                Button("Print PDF", systemImage: "printer", action: printPDF)
                    .disabled(!(pdfDocument?.allowsPrinting ?? false))
                Button("Protect PDF", systemImage: "lock.doc") { showingProtectSheet = true }
                    .disabled(pdfDocument == nil)
            } label: { Label("File", systemImage: "folder") }
                .buttonStyle(.bordered)
            Menu {
                Button("Continuous pages", systemImage: "list.bullet") { displayMode = .singlePageContinuous }
                Button("Single page", systemImage: "doc") { displayMode = .singlePage }
                Button("Two page spread", systemImage: "book") { displayMode = .twoUpContinuous }
            } label: { Label("View", systemImage: "rectangle.split.2x1") }
                .buttonStyle(.bordered).disabled(pdfDocument == nil)
            Menu {
                Button("Add bookmark", systemImage: "bookmark", action: addBookmark)
                ForEach(bookmarkedPages, id: \.self) { page in
                    Button("Go to page \(page)") { goToPage(page) }
                }
                Divider()
                Button("Highlight selection", systemImage: "highlighter") { addMarkup(.highlight) }
                    .disabled(pdfView?.currentSelection == nil || !(pdfDocument?.allowsCommenting ?? false))
                Button("Underline selection", systemImage: "underline") { addMarkup(.underline) }
                    .disabled(pdfView?.currentSelection == nil || !(pdfDocument?.allowsCommenting ?? false))
                Button("Mark selected text for redaction", systemImage: "eye.slash", action: markSelectionForRedaction)
                    .disabled(pdfView?.currentSelection == nil)
                Button("Clear redaction marks", systemImage: "xmark.rectangle", role: .destructive, action: clearRedactionMarks)
                    .disabled(redactionCount == 0)
                Divider()
                Button("Add note to page", systemImage: "text.bubble") { textPrompt = .note }
                    .disabled(!(pdfDocument?.allowsCommenting ?? false))
                Button("Add typed signature", systemImage: "signature") { textPrompt = .signature }
                    .disabled(!(pdfDocument?.allowsCommenting ?? false))
                Button("Move page up", systemImage: "arrow.up", action: { moveCurrentPage(by: -1) })
                    .disabled(currentPage <= 1 || !(pdfDocument?.allowsDocumentAssembly ?? false))
                Button("Move page down", systemImage: "arrow.down", action: { moveCurrentPage(by: 1) })
                    .disabled(currentPage >= (pdfDocument?.pageCount ?? 0) || !(pdfDocument?.allowsDocumentAssembly ?? false))
                Button("Rotate current page", systemImage: "rotate.right", action: rotateCurrentPage)
                    .disabled(!(pdfDocument?.allowsDocumentAssembly ?? false))
                Button("Delete current page", systemImage: "trash", role: .destructive, action: deleteCurrentPage)
                    .disabled((pdfDocument?.pageCount ?? 0) <= 1 || !(pdfDocument?.allowsDocumentAssembly ?? false))
            } label: { Label("Annotate", systemImage: "pencil.and.outline") }
                .buttonStyle(.bordered).disabled(pdfDocument == nil)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.bar)
    }

    private var searchBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in document", text: $searchText)
                .textFieldStyle(.plain).submitLabel(.search).onSubmit(searchDocument)
            if !searchText.isEmpty {
                Button { searchText = ""; searchResults = []; pdfView?.clearSelection() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
            Button("Find", action: searchDocument).buttonStyle(.borderedProminent)
            Button { moveSearch(by: -1) } label: { Image(systemName: "chevron.up") }.disabled(searchResults.isEmpty)
            Button { moveSearch(by: 1) } label: { Image(systemName: "chevron.down") }.disabled(searchResults.isEmpty)
            if !searchResults.isEmpty {
                Text("\(searchIndex + 1) / \(searchResults.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 56)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Button { goToPage(currentPage - 1) } label: { Image(systemName: "chevron.left") }.disabled(currentPage <= 1)
            TextField("Page", text: $pageInput)
                .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center).frame(width: 58)
                .onSubmit { goToPage(Int(pageInput) ?? 1) }
            Text("of \(pdfDocument?.pageCount ?? 0)").font(.caption).foregroundStyle(.secondary)
            Button { goToPage(Int(pageInput) ?? 1) } label: { Image(systemName: "arrow.right.to.line") }
            Spacer()
            if let statusMessage {
                Text(statusMessage).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Button { adjustZoom(by: 1 / 1.2) } label: { Image(systemName: "minus.magnifyingglass") }
            Text("\(Int((pdfView?.scaleFactor ?? 1) * 100))%").font(.caption.monospacedDigit()).frame(minWidth: 46)
            Button { adjustZoom(by: 1.2) } label: { Image(systemName: "plus.magnifyingglass") }
            if let exportURL {
                ShareLink(item: exportURL) { Image(systemName: "square.and.arrow.up") }
            } else {
                Button { exportPDF() } label: { Image(systemName: "square.and.arrow.up") }
            }
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.bar)
    }

    private var currentPage: Int { Int(pageInput) ?? 1 }
    private var filteredOCRLines: [PDFOCRLine] {
        let query = ocrSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return ocrLines }
        return ocrLines.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    private var redactionCount: Int {
        guard let pdfDocument else { return 0 }
        return (0..<pdfDocument.pageCount).compactMap { pdfDocument.page(at: $0) }
            .reduce(0) { count, page in count + page.annotations.filter { $0.userName == pdfRedactionAuthor }.count }
    }

    private var formFields: [(annotation: PDFAnnotation, pageNumber: Int)] {
        guard let pdfDocument else { return [] }
        return (0..<pdfDocument.pageCount).flatMap { index -> [(PDFAnnotation, Int)] in
            guard let page = pdfDocument.page(at: index) else { return [] }
            return page.annotations.compactMap { annotation in
                guard annotation.type == PDFAnnotationSubtype.widget,
                      annotation.widgetFieldType == .text || annotation.widgetFieldType == .choice ||
                        (annotation.widgetFieldType == .button && annotation.widgetControlType == .checkBoxControl),
                      !annotation.isReadOnly else { return nil }
                return (annotation, index + 1)
            }
        }
    }

    private func formFieldBinding(_ annotation: PDFAnnotation) -> Binding<String> {
        Binding(
            get: { annotation.widgetStringValue ?? "" },
            set: { value in
                annotation.widgetStringValue = value
                pdfView?.setNeedsDisplay()
                exportURL = nil
                statusMessage = "Form value updated"
            }
        )
    }

    private func formFieldTitle(_ annotation: PDFAnnotation, index: Int) -> String {
        let name = annotation.fieldName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Field \(index + 1)" : name
    }

    private func checkboxBinding(_ annotation: PDFAnnotation) -> Binding<Bool> {
        Binding(
            get: { annotation.buttonWidgetState == .onState },
            set: { isChecked in
                annotation.buttonWidgetState = isChecked ? .onState : .offState
                pdfView?.setNeedsDisplay()
                exportURL = nil
                statusMessage = "Form value updated"
            }
        )
    }

    private func beginImport(merge: Bool) {
        mergeNextImport = merge
        showingImporter = true
    }

    private func unlockDocument() {
        guard let pdfDocument else { return }
        if pdfDocument.unlock(withPassword: unlockPassword) {
            showingUnlockPrompt = false
            pdfView = nil
            statusMessage = "PDF unlocked"
            unlockPassword = ""
        } else {
            statusMessage = "That password did not unlock the PDF."
        }
    }

    private func importPDFs(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }
            if mergeNextImport {
                let merged = PDFDocument()
                for url in urls {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    guard let source = PDFDocument(data: data), !source.isLocked else { throw CocoaError(.fileReadCorruptFile) }
                    for index in 0..<source.pageCount {
                        if let page = source.page(at: index) { merged.insert(page, at: merged.pageCount) }
                    }
                }
                guard merged.pageCount > 0 else { throw CocoaError(.fileReadCorruptFile) }
                pdfDocument = merged
                fileName = "Merged PDF (\(urls.count) files)"
                bookmarkIdentity = urls.map { $0.standardizedFileURL.path }.joined(separator: "\n")
                statusMessage = "Merged \(urls.count) PDFs"
            } else {
                guard let url = urls.first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                guard let document = PDFDocument(data: data) else { throw CocoaError(.fileReadCorruptFile) }
                pdfDocument = document
                fileName = url.lastPathComponent
                bookmarkIdentity = url.standardizedFileURL.path
                statusMessage = document.isLocked ? "Password required" : nil
                showingUnlockPrompt = document.isLocked
            }
            pdfView = nil
            searchResults = []
            searchText = ""
            ocrLines = []
            ocrSearchText = ""
            let defaults = UserDefaults.standard
            if let stored = defaults.array(forKey: bookmarkKey) as? [Int] {
                bookmarkedPages = stored
            } else {
                let legacyKey = "artcraft.pdfcraft.bookmarks." + (fileName.isEmpty ? "current" : fileName)
                bookmarkedPages = defaults.array(forKey: legacyKey) as? [Int] ?? []
                if !bookmarkedPages.isEmpty { defaults.set(bookmarkedPages, forKey: bookmarkKey) }
            }
            pageInput = "1"
            exportURL = nil
        } catch {
            statusMessage = "Could not open the selected PDF file(s)."
        }
    }

    private func goToPage(_ pageNumber: Int) {
        guard let pdfDocument, pdfDocument.pageCount > 0 else { return }
        let safeNumber = min(max(1, pageNumber), pdfDocument.pageCount)
        pageInput = String(safeNumber)
        if let page = pdfDocument.page(at: safeNumber - 1) { pdfView?.go(to: page) }
    }

    private func searchDocument() {
        guard let pdfDocument, !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        searchResults = pdfDocument.findString(searchText, withOptions: [.caseInsensitive])
        searchIndex = 0
        if let match = searchResults.first {
            pdfView?.setCurrentSelection(match, animate: true)
            pdfView?.go(to: match)
        }
        statusMessage = searchResults.isEmpty ? "No matches found" : "Found \(searchResults.count) matches"
    }

    private func moveSearch(by offset: Int) {
        guard !searchResults.isEmpty else { return }
        searchIndex = (searchIndex + offset + searchResults.count) % searchResults.count
        let selection = searchResults[searchIndex]
        pdfView?.setCurrentSelection(selection, animate: true)
        pdfView?.go(to: selection)
    }

    private func addBookmark() {
        guard let page = pdfView?.currentPage, let pdfDocument else { return }
        let pageNumber = pdfDocument.index(for: page) + 1
        if !bookmarkedPages.contains(pageNumber) {
            bookmarkedPages.append(pageNumber)
            bookmarkedPages.sort()
            UserDefaults.standard.set(bookmarkedPages, forKey: bookmarkKey)
            statusMessage = "Bookmarked page \(pageNumber)"
        }
    }

    private func addMarkup(_ type: PDFAnnotationSubtype) {
        guard let selection = pdfView?.currentSelection else { return }
        var added = 0
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                guard !bounds.isNull, !bounds.isEmpty else { continue }
                let annotation = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
                annotation.quadrilateralPoints = [
                    NSValue(cgPoint: CGPoint(x: 0, y: bounds.height)),
                    NSValue(cgPoint: CGPoint(x: bounds.width, y: bounds.height)),
                    NSValue(cgPoint: CGPoint.zero),
                    NSValue(cgPoint: CGPoint(x: bounds.width, y: 0))
                ]
                annotation.color = type == .underline ? .systemBlue : .systemYellow.withAlphaComponent(0.45)
                page.addAnnotation(annotation)
                added += 1
            }
        }
        if added > 0 { exportURL = nil }
        statusMessage = added > 0 ? "Annotation added" : "Select text before annotating"
    }

    private func markSelectionForRedaction() {
        guard let selection = pdfView?.currentSelection else { return }
        var added = 0
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                guard !bounds.isNull, !bounds.isEmpty else { continue }
                addRedactionMark(on: page, bounds: bounds)
                added += 1
            }
        }
        if added > 0 {
            pdfView?.clearSelection()
            pdfView?.setNeedsDisplay()
            exportURL = nil
        }
        statusMessage = added > 0 ? "Redaction marked. Export a redacted copy to remove the selected content." : "Select text before marking it for redaction"
    }

    private func addRedactionMark(onPage pageIndex: Int, bounds: CGRect) {
        guard let page = pdfDocument?.page(at: pageIndex) else { return }
        addRedactionMark(on: page, bounds: bounds)
        pdfView?.setNeedsDisplay()
        exportURL = nil
        statusMessage = "OCR line marked. Export a redacted copy to remove the marked content."
    }

    private func addRedactionMark(on page: PDFPage, bounds: CGRect) {
        let pageBounds = page.bounds(for: .cropBox)
        let safeBounds = bounds.insetBy(dx: -1.5, dy: -2).intersection(pageBounds)
        guard !safeBounds.isNull, !safeBounds.isEmpty else { return }
        let annotation = PDFAnnotation(bounds: safeBounds, forType: .square, withProperties: nil)
        annotation.userName = pdfRedactionAuthor
        annotation.color = .black
        annotation.interiorColor = .black
        annotation.border = PDFBorder()
        annotation.border?.lineWidth = 0
        page.addAnnotation(annotation)
    }

    private func clearOCRResults() {
        ocrLines = []
        ocrSearchText = ""
        showingOCRSheet = false
    }

    private func recognizeText() {
        guard let sourceDocument = pdfDocument,
              let data = sourceDocument.dataRepresentation(), !isRecognizingOCR else { return }
        isRecognizingOCR = true
        statusMessage = "Recognizing text in scanned pages…"
        Task {
            let lines = await Task.detached(priority: .userInitiated) { Self.performOCR(on: data) }.value
            guard pdfDocument === sourceDocument else {
                isRecognizingOCR = false
                return
            }
            ocrLines = lines
            isRecognizingOCR = false
            ocrSearchText = ""
            showingOCRSheet = true
            statusMessage = lines.isEmpty ? "No text was recognized" : "Recognized \(lines.count) text lines"
        }
    }

    private static func performOCR(on data: Data) -> [PDFOCRLine] {
        guard let document = PDFDocument(data: data), !document.isLocked else { return [] }
        var lines: [PDFOCRLine] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let pageBounds = page.bounds(for: .cropBox)
            guard pageBounds.width > 0, pageBounds.height > 0 else { continue }
            let thumbnail = page.thumbnail(of: CGSize(width: 1800, height: 1800), for: .cropBox)
            guard let cgImage = thumbnail.cgImage else { continue }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            } catch { continue }
            let rotation = ((page.rotation % 360) + 360) % 360
            for observation in (request.results ?? []).sorted(by: { $0.boundingBox.midY > $1.boundingBox.midY }) {
                guard let recognized = observation.topCandidates(1).first?.string,
                      !recognized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let box = observation.boundingBox
                let corners = [
                    CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.minX, y: box.maxY),
                    CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.maxX, y: box.maxY)
                ].map { point -> CGPoint in
                    let x: CGFloat
                    let y: CGFloat
                    switch rotation {
                    case 90: x = 1 - point.y; y = point.x
                    case 180: x = 1 - point.x; y = 1 - point.y
                    case 270: x = point.y; y = 1 - point.x
                    default: x = point.x; y = point.y
                    }
                    return CGPoint(x: pageBounds.minX + x * pageBounds.width, y: pageBounds.minY + y * pageBounds.height)
                }
                let xs = corners.map(\.x)
                let ys = corners.map(\.y)
                let bounds = CGRect(x: xs.min() ?? pageBounds.minX, y: ys.min() ?? pageBounds.minY,
                                    width: (xs.max() ?? pageBounds.minX) - (xs.min() ?? pageBounds.minX),
                                    height: (ys.max() ?? pageBounds.minY) - (ys.min() ?? pageBounds.minY))
                lines.append(PDFOCRLine(pageIndex: pageIndex, text: recognized, bounds: bounds))
            }
        }
        return lines
    }

    private func clearRedactionMarks() {
        guard let pdfDocument else { return }
        for index in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: index) else { continue }
            page.annotations.filter { $0.userName == pdfRedactionAuthor }.forEach { page.removeAnnotation($0) }
        }
        pdfView?.setNeedsDisplay()
        exportURL = nil
        statusMessage = "Redaction marks cleared"
    }

    private func rotateCurrentPage() {
        guard let page = pdfView?.currentPage else { return }
        page.rotation = (page.rotation + 90) % 360
        clearOCRResults()
        pdfView?.setNeedsDisplay()
        exportURL = nil
        statusMessage = "Page rotated"
    }

    private func moveCurrentPage(by offset: Int) {
        guard let pdfDocument else { return }
        let source = currentPage - 1
        let destination = source + offset
        guard pdfDocument.pageCount > 1,
              source >= 0,
              destination >= 0,
              destination < pdfDocument.pageCount,
              pdfDocument.page(at: destination) != nil else { return }
        pdfDocument.exchangePage(at: source, withPageAt: destination)
        clearOCRResults()
        bookmarkedPages = bookmarkedPages.map { page in
            if page == source + 1 { return destination + 1 }
            if page == destination + 1 { return source + 1 }
            return page
        }.sorted()
        UserDefaults.standard.set(bookmarkedPages, forKey: bookmarkKey)
        goToPage(destination + 1)
        exportURL = nil
        statusMessage = "Page moved"
    }

    private func addNote() {
        defer { noteText = "" }
        guard let page = pdfDocument?.page(at: currentPage - 1),
              !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let bounds = page.bounds(for: .cropBox)
        let noteBounds = CGRect(x: bounds.minX + 24, y: bounds.maxY - 100, width: min(260, bounds.width - 48), height: 64)
        let annotation = PDFAnnotation(bounds: noteBounds, forType: .freeText, withProperties: nil)
        annotation.contents = noteText
        annotation.font = .systemFont(ofSize: 14)
        annotation.fontColor = .label
        annotation.color = UIColor.systemYellow.withAlphaComponent(0.18)
        page.addAnnotation(annotation)
        exportURL = nil
        statusMessage = "Note added to page \(currentPage)"
    }

    private func submitTextPrompt() {
        switch textPrompt {
        case .note: addNote()
        case .signature: addSignature()
        case nil: break
        }
        textPrompt = nil
    }

    private func addSignature() {
        defer { signatureText = "" }
        guard let page = pdfDocument?.page(at: currentPage - 1),
              !signatureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let pageBounds = page.bounds(for: .cropBox)
        let signatureBounds = CGRect(x: pageBounds.maxX - 250, y: pageBounds.minY + 42, width: 210, height: 52)
        let annotation = PDFAnnotation(bounds: signatureBounds, forType: .freeText, withProperties: nil)
        annotation.contents = signatureText
        annotation.font = UIFont(name: "SnellRoundhand", size: 28) ?? .italicSystemFont(ofSize: 28)
        annotation.fontColor = .systemBlue
        annotation.color = .clear
        page.addAnnotation(annotation)
        exportURL = nil
        statusMessage = "Typed signature added"
    }

    private func deleteCurrentPage() {
        guard let pdfDocument, pdfDocument.pageCount > 1 else { return }
        let index = min(max(0, currentPage - 1), pdfDocument.pageCount - 1)
        pdfDocument.removePage(at: index)
        clearOCRResults()
        bookmarkedPages = bookmarkedPages.compactMap { page in
            if page == index + 1 { return nil }
            return page > index + 1 ? page - 1 : page
        }
        UserDefaults.standard.set(bookmarkedPages, forKey: bookmarkKey)
        goToPage(min(index + 1, pdfDocument.pageCount))
        exportURL = nil
        statusMessage = "Page deleted"
    }

    private func adjustZoom(by multiplier: CGFloat) {
        guard let pdfView else { return }
        pdfView.scaleFactor = min(pdfView.maxScaleFactor, max(pdfView.minScaleFactor, pdfView.scaleFactor * multiplier))
    }

    private func exportPDF() {
        guard let pdfDocument else { return }
        let name = safeFileName(URL(fileURLWithPath: fileName.isEmpty ? "Document.pdf" : fileName).deletingPathExtension().lastPathComponent) + ".pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard pdfDocument.write(to: url) else { statusMessage = "Could not export PDF"; return }
        exportURL = url
        statusMessage = "Export ready"
    }

    private func exportFlattenedPDF() {
        guard let pdfDocument else { return }
        let baseName = URL(fileURLWithPath: fileName.isEmpty ? "Document.pdf" : fileName).deletingPathExtension().lastPathComponent
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeFileName(baseName) + "-flattened.pdf")
        guard pdfDocument.write(to: url, withOptions: [.burnInAnnotationsOption: true]) else {
            statusMessage = "Could not flatten annotations"
            return
        }
        exportURL = url
        statusMessage = "Flattened copy ready"
    }

    private func exportRedactedPDF() {
        guard let pdfDocument, redactionCount > 0 else { return }
        let baseName = URL(fileURLWithPath: fileName.isEmpty ? "Document.pdf" : fileName).deletingPathExtension().lastPathComponent
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeFileName(baseName) + "-redacted.pdf")
        let maximumBounds = (0..<pdfDocument.pageCount).compactMap { pdfDocument.page(at: $0)?.bounds(for: .cropBox) }
            .reduce(CGSize(width: 612, height: 792)) { CGSize(width: max($0.width, $1.width), height: max($0.height, $1.height)) }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: maximumBounds))
        do {
            let data = renderer.pdfData { context in
                for index in 0..<pdfDocument.pageCount {
                    guard let page = pdfDocument.page(at: index) else { continue }
                    let pageBounds = page.bounds(for: .cropBox)
                    guard pageBounds.width > 0, pageBounds.height > 0 else { continue }
                    context.beginPage(withBounds: CGRect(origin: .zero, size: pageBounds.size), pageInfo: [:])
                    let markedAreas = page.annotations
                        .filter { $0.userName == pdfRedactionAuthor }
                        .map(\.bounds)
                    let format = UIGraphicsImageRendererFormat.default()
                    format.opaque = true
                    format.scale = min(2, 4096 / max(pageBounds.width, pageBounds.height))
                    let image = UIGraphicsImageRenderer(size: pageBounds.size, format: format).image { imageContext in
                        UIColor.white.setFill()
                        imageContext.fill(CGRect(origin: .zero, size: pageBounds.size))
                        let cgContext = imageContext.cgContext
                        cgContext.saveGState()
                        cgContext.translateBy(x: -pageBounds.minX, y: pageBounds.maxY)
                        cgContext.scaleBy(x: 1, y: -1)
                        page.draw(with: .cropBox, to: cgContext)
                        cgContext.restoreGState()
                        cgContext.setFillColor(UIColor.black.cgColor)
                        for area in markedAreas {
                            let rect = CGRect(x: area.minX - pageBounds.minX, y: pageBounds.maxY - area.maxY, width: area.width, height: area.height)
                            cgContext.fill(rect)
                        }
                    }
                    image.draw(in: CGRect(origin: .zero, size: pageBounds.size))
                }
            }
            try data.write(to: url, options: .atomic)
            exportURL = url
            statusMessage = "Redacted copy ready. Page content is rasterized and marked areas cannot be recovered from the copy."
        } catch {
            statusMessage = "Could not create the redacted copy"
        }
    }

    private func exportSearchableOCRPDF() {
        guard let pdfDocument, !ocrLines.isEmpty else { return }
        guard redactionCount == 0 else {
            statusMessage = "Export a redacted copy separately; searchable OCR export is disabled while redaction marks exist."
            return
        }
        let baseName = URL(fileURLWithPath: fileName.isEmpty ? "Document.pdf" : fileName).deletingPathExtension().lastPathComponent
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeFileName(baseName) + "-searchable.pdf")
        let maximumBounds = (0..<pdfDocument.pageCount).compactMap { pdfDocument.page(at: $0)?.bounds(for: .cropBox) }
            .reduce(CGSize(width: 612, height: 792)) { CGSize(width: max($0.width, $1.width), height: max($0.height, $1.height)) }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: maximumBounds))
        let data = renderer.pdfData { rendererContext in
            for pageIndex in 0..<pdfDocument.pageCount {
                guard let page = pdfDocument.page(at: pageIndex) else { continue }
                let pageBounds = page.bounds(for: .cropBox)
                guard pageBounds.width > 0, pageBounds.height > 0 else { continue }
                rendererContext.beginPage(withBounds: CGRect(origin: .zero, size: pageBounds.size), pageInfo: [:])
                let context = rendererContext.cgContext
                context.saveGState()
                context.translateBy(x: -pageBounds.minX, y: pageBounds.maxY)
                context.scaleBy(x: 1, y: -1)
                page.draw(with: .cropBox, to: context)
                context.restoreGState()

                for line in ocrLines where line.pageIndex == pageIndex {
                    guard !line.bounds.isNull, !line.bounds.isEmpty else { continue }
                    let fontSize = min(36, max(6, line.bounds.height * 0.85))
                    let attributedText = NSAttributedString(string: line.text, attributes: [.font: UIFont.systemFont(ofSize: fontSize)])
                    let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
                    let textPath = CGPath(rect: line.bounds, transform: nil)
                    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attributedText.length), textPath, nil)
                    context.saveGState()
                    context.translateBy(x: -pageBounds.minX, y: pageBounds.maxY)
                    context.scaleBy(x: 1, y: -1)
                    context.setTextMatrix(.identity)
                    context.setTextDrawingMode(.invisible)
                    CTFrameDraw(frame, context)
                    context.restoreGState()
                }
            }
        }
        do {
            try data.write(to: url, options: .atomic)
            exportURL = url
            statusMessage = "Searchable OCR PDF ready"
        } catch {
            statusMessage = "Could not export the searchable OCR PDF"
        }
    }

    private func printPDF() {
        guard let pdfDocument, pdfDocument.allowsPrinting,
              let data = pdfDocument.dataRepresentation() else { return }
        let controller = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = fileName.isEmpty ? "PdfCraft Document" : fileName
        printInfo.outputType = .general
        controller.printInfo = printInfo
        controller.printingItem = data
        controller.present(animated: true, completionHandler: nil)
    }

    private func exportCurrentPage() {
        guard let pdfDocument, let page = pdfDocument.page(at: max(0, min(currentPage - 1, pdfDocument.pageCount - 1))) else { return }
        let single = PDFDocument()
        single.insert(page, at: 0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Page-\(currentPage).pdf")
        guard single.write(to: url) else { statusMessage = "Could not export page"; return }
        exportURL = url
        statusMessage = "Page export ready"
    }

    private func exportPageRange() {
        guard let pdfDocument, pdfDocument.pageCount > 0 else { return }
        let first = Int(splitStartPage) ?? 1
        let last = Int(splitEndPage) ?? first
        let start = min(max(1, min(first, last)), pdfDocument.pageCount)
        let end = min(max(start, max(first, last)), pdfDocument.pageCount)
        let extracted = PDFDocument()
        for pageIndex in (start - 1)..<end {
            if let page = pdfDocument.page(at: pageIndex) { extracted.insert(page, at: extracted.pageCount) }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Pages-\(start)-\(end).pdf")
        guard extracted.pageCount > 0, extracted.write(to: url) else {
            statusMessage = "Could not export the selected pages"
            return
        }
        exportURL = url
        statusMessage = "Pages \(start)-\(end) ready"
        showingSplitSheet = false
    }

    private func exportProtectedPDF() {
        guard let pdfDocument else { return }
        var permissions: PDFAccessPermissions = [.allowsContentAccessibility]
        if allowPrinting { permissions.insert(.allowsHighQualityPrinting) }
        if allowCopying { permissions.insert(.allowsContentCopying) }
        if allowAnnotations { permissions.insert(.allowsCommenting) }
        if allowPageAssembly { permissions.insert(.allowsDocumentAssembly) }

        var options: [PDFDocumentWriteOption: Any] = [
            .ownerPasswordOption: ownerPassword as NSString,
            .accessPermissionsOption: permissions.rawValue
        ]
        if !userPassword.isEmpty { options[.userPasswordOption] = userPassword as NSString }
        let baseName = URL(fileURLWithPath: fileName.isEmpty ? "Document.pdf" : fileName).deletingPathExtension().lastPathComponent
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeFileName(baseName) + "-protected.pdf")
        guard pdfDocument.write(to: url, withOptions: options) else {
            statusMessage = "Could not protect PDF"
            return
        }
        exportURL = url
        statusMessage = "Protected copy ready"
        showingProtectSheet = false
        ownerPassword = ""
        userPassword = ""
    }

    private var bookmarkKey: String {
        let identity = bookmarkIdentity.isEmpty ? fileName : bookmarkIdentity
        let digest = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "artcraft.pdfcraft.bookmarks." + digest
    }
}

private struct PDFDocumentSurface: UIViewRepresentable {
    let document: PDFDocument
    let displayMode: PDFDisplayMode
    let onReady: (PDFView) -> Void

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = displayMode
        view.displayDirection = .vertical
        view.backgroundColor = UIColor.secondarySystemBackground
        view.document = document
        DispatchQueue.main.async { [onReady] in onReady(view) }
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        view.document = document
        view.displayMode = displayMode
        DispatchQueue.main.async { [onReady] in onReady(view) }
    }
}

private struct PDFThumbnailRail: UIViewRepresentable {
    let pdfView: PDFView
    func makeUIView(context: Context) -> PDFThumbnailView {
        let view = PDFThumbnailView()
        view.pdfView = pdfView
        view.thumbnailSize = CGSize(width: 116, height: 150)
        view.layoutMode = .vertical
        view.allowsDragging = false
        view.backgroundColor = UIColor.secondarySystemBackground
        return view
    }
    func updateUIView(_ view: PDFThumbnailView, context: Context) {
        view.pdfView = pdfView
        view.allowsDragging = false
    }
}
