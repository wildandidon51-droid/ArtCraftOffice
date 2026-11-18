import SwiftUI
import UniformTypeIdentifiers
import UIKit
import Charts

struct GridCellStyle: Codable, Equatable {
    var bold = false
    var italic = false
    var fill: String? = nil
    var numberFormat: String? = nil
    var border: String? = nil

    var isDefault: Bool { !bold && !italic && fill == nil && numberFormat == nil && border == nil }
}

private struct GridClipboardCell {
    let value: String
    let row: Int
    let column: Int
    let style: GridCellStyle
}

private struct GridColumnFilter: Equatable {
    let sheetID: UUID
    let column: Int
    let value: String?
}

private struct GridFilterOption: Identifiable {
    let value: String?
    var id: String { value.map { "value:\($0)" } ?? "blank" }
    var title: String { value.flatMap { $0.isEmpty ? nil : $0 } ?? "(Blanks)" }
}

private struct GridChart: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var sheetID: UUID
    var categoryColumn: Int
    var valueColumn: Int
    var firstDataRow: Int
    var lastDataRow: Int
    var kind = "column"
}

private struct GridChartPoint: Identifiable {
    let row: Int
    let category: String
    let value: Double
    var id: Int { row }
}

private struct GridChartCard: View {
    let chart: GridChart
    let points: [GridChartPoint]
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(chart.title).font(.headline)
                Spacer()
                Button("Remove chart", systemImage: "trash", role: .destructive, action: onDelete)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
            }
            if points.isEmpty {
                ContentUnavailableView("No numeric data", systemImage: "chart.bar", description: Text("Enter numeric values in the source column to populate this chart."))
                    .frame(height: 190)
            } else {
                Chart(points) { point in
                    if chart.kind == "line" {
                        LineMark(x: .value("Category", point.category), y: .value(chart.title, point.value))
                            .foregroundStyle(Color.accentColor)
                        PointMark(x: .value("Category", point.category), y: .value(chart.title, point.value))
                            .foregroundStyle(Color.accentColor)
                    } else {
                        BarMark(x: .value("Category", point.category), y: .value(chart.title, point.value))
                            .foregroundStyle(Color.accentColor.gradient)
                    }
                }
                .chartYAxisLabel(chart.title)
                .frame(height: 230)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(uiColor: .separator).opacity(0.3)))
        .padding(.top, 10)
    }
}

private struct GridSheet: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = "Sheet1"
    var cells: [[String]] = Self.emptyCells
    var styles: [String: GridCellStyle] = [:]

    static var emptyCells: [[String]] {
        var values = Array(repeating: Array(repeating: "", count: 12), count: 30)
        values[0][0] = "Item"
        values[0][1] = "Quantity"
        values[0][2] = "Price"
        values[0][3] = "Total"
        return values
    }

    init(id: UUID = UUID(), name: String = "Sheet1", cells: [[String]] = Self.emptyCells, styles: [String: GridCellStyle] = [:]) {
        self.id = id
        self.name = name
        self.cells = cells
        self.styles = styles
    }

    private enum CodingKeys: String, CodingKey { case id, name, cells, styles }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "Sheet1"
        cells = try values.decodeIfPresent([[String]].self, forKey: .cells) ?? Self.emptyCells
        styles = try values.decodeIfPresent([String: GridCellStyle].self, forKey: .styles) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(cells, forKey: .cells)
        try values.encode(styles, forKey: .styles)
    }
}

private struct GridWorkbook: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = "Untitled Spreadsheet"
    var sheets = [GridSheet]()
    var charts: [GridChart] = []

    init(id: UUID = UUID(), title: String = "Untitled Spreadsheet", sheets: [GridSheet] = [GridSheet()], charts: [GridChart] = []) {
        self.id = id
        self.title = title
        self.sheets = sheets.isEmpty ? [GridSheet()] : sheets
        self.charts = charts
    }

    private enum CodingKeys: String, CodingKey { case id, title, sheets, cells, charts }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Spreadsheet"
        if let decoded = try values.decodeIfPresent([GridSheet].self, forKey: .sheets), !decoded.isEmpty {
            sheets = decoded
        } else {
            sheets = [GridSheet(name: "Sheet1", cells: try values.decodeIfPresent([[String]].self, forKey: .cells) ?? GridSheet.emptyCells)]
        }
        charts = try values.decodeIfPresent([GridChart].self, forKey: .charts) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(title, forKey: .title)
        try values.encode(sheets, forKey: .sheets)
        try values.encode(charts, forKey: .charts)
    }
}

private struct GridAddress: Equatable {
    var row = 0
    var column = 0
    var label: String { "\(GridCraftView.columnName(column))\(row + 1)" }
}

private enum GridRibbonTab: String, CaseIterable {
    case home = "Home"
    case insert = "Insert"
    case formulas = "Formulas"
    case data = "Data"
    case view = "View"
}

struct GridCraftView: View {
    @State private var workbook: GridWorkbook
    @State private var savedWorkbooks: [GridWorkbook]
    @State private var activeImporter = false
    @State private var exportURL: URL?
    @State private var selected = GridAddress()
    @State private var copiedCell: GridClipboardCell?
    @State private var selectedSheetID: UUID
    @State private var showingRenameSheet = false
    @State private var sheetNameDraft = ""
    @State private var selectedRibbonTab: GridRibbonTab = .home
    @State private var showsGridlines = true
    @State private var undoStack: [GridWorkbook] = []
    @State private var redoStack: [GridWorkbook] = []
    @State private var isRestoringHistory = false
    @State private var activeFilter: GridColumnFilter?
    @State private var zoom: Double = 1
    @State private var statusMessage = "All changes saved"
    @State private var pendingSave: Task<Void, Never>?
    @FocusState private var formulaFocused: Bool

    private let legacyKey = "artcraft.gridcraft.workbook.v1"
    private var zoomScale: CGFloat { CGFloat(zoom) }
    private var rowHeaderWidth: CGFloat { 48 * zoomScale }
    private var columnWidth: CGFloat { 132 * zoomScale }

    init() {
        if let saved = Self.loadLibrary() {
            _savedWorkbooks = State(initialValue: saved)
            let initial = saved.first ?? GridWorkbook()
            _workbook = State(initialValue: initial)
            _selectedSheetID = State(initialValue: initial.sheets[0].id)
        } else if let data = UserDefaults.standard.data(forKey: "artcraft.gridcraft.library.v1"),
                  let saved = try? JSONDecoder().decode([GridWorkbook].self, from: data) {
            _savedWorkbooks = State(initialValue: saved)
            let initial = saved.first ?? GridWorkbook()
            _workbook = State(initialValue: initial)
            _selectedSheetID = State(initialValue: initial.sheets[0].id)
        } else if let data = UserDefaults.standard.data(forKey: "artcraft.gridcraft.workbook.v1"),
                  let legacy = try? JSONDecoder().decode(GridWorkbook.self, from: data) {
            _savedWorkbooks = State(initialValue: [legacy])
            _workbook = State(initialValue: legacy)
            _selectedSheetID = State(initialValue: legacy.sheets[0].id)
        } else {
            let initial = GridWorkbook()
            _savedWorkbooks = State(initialValue: [])
            _workbook = State(initialValue: initial)
            _selectedSheetID = State(initialValue: initial.sheets[0].id)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            formulaBar
            Divider()
            spreadsheetGrid
            Divider()
            sheetTabs
            Divider()
            HStack {
                Label(statusMessage, systemImage: "checkmark.circle")
                Spacer()
                Text("\(workbook.sheets[activeSheetIndex].cells.count) rows · \(workbook.sheets[activeSheetIndex].cells.first?.count ?? 0) columns")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(.bar)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onChange(of: workbook) { oldValue, newValue in
            if isRestoringHistory {
                isRestoringHistory = false
            } else {
                undoStack.append(oldValue)
                if undoStack.count > 30 { undoStack.removeFirst(undoStack.count - 30) }
                redoStack.removeAll(keepingCapacity: true)
            }
            scheduleSave(newValue)
        }
        .onDisappear {
            pendingSave?.cancel()
            persist(workbook)
        }
        .fileImporter(isPresented: $activeImporter, allowedContentTypes: [.commaSeparatedText, .plainText, UTType(filenameExtension: "xlsx") ?? .data], allowsMultipleSelection: false) { result in
            importSpreadsheet(result)
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                TextField("Spreadsheet title", text: $workbook.title)
                    .font(.headline).textFieldStyle(.plain).frame(maxWidth: 280)
                Text(statusMessage).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 8)
                Menu {
                    Button("New spreadsheet", systemImage: "doc.badge.plus") { newWorkbook() }
                    if !savedWorkbooks.isEmpty {
                        Menu("Open saved spreadsheet") {
                            ForEach(savedWorkbooks) { saved in
                                Button(saved.title) { openWorkbook(saved.id) }
                            }
                        }
                    }
                    Divider()
                Button("Open workbook", systemImage: "folder") { activeImporter = true }
                    Button("Export Excel workbook", systemImage: "tablecells", action: exportXLSX)
                    Button("Export current sheet as CSV", systemImage: "square.and.arrow.up", action: exportCSV)
                    if let exportURL { ShareLink(item: exportURL) { Label("Share last export", systemImage: "square.and.arrow.up") } }
                } label: { Label("File", systemImage: "line.3.horizontal") }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16).padding(.vertical, 9)

            HStack(spacing: 22) {
                ForEach(GridRibbonTab.allCases, id: \.self) { tab in
                    Button { selectedRibbonTab = tab } label: {
                        VStack(spacing: 7) {
                            Text(tab.rawValue)
                                .font(.subheadline.weight(selectedRibbonTab == tab ? .semibold : .regular))
                                .foregroundStyle(selectedRibbonTab == tab ? Color.accentColor : Color.primary)
                            Capsule().fill(selectedRibbonTab == tab ? Color.accentColor : .clear).frame(height: 3)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(height: 39)

            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                ribbonCommands
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 16)
            }
            .frame(height: 58)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .background(Color(uiColor: .systemBackground))
    }

    @ViewBuilder
    private var ribbonCommands: some View {
        switch selectedRibbonTab {
        case .home:
            HStack(spacing: 10) {
                Button(action: undo) { Label("Undo", systemImage: "arrow.uturn.backward").frame(minHeight: 42).padding(.horizontal, 9) }
                    .buttonStyle(.bordered).disabled(undoStack.isEmpty).keyboardShortcut("z", modifiers: .command)
                Button(action: redo) { Label("Redo", systemImage: "arrow.uturn.forward").frame(minHeight: 42).padding(.horizontal, 9) }
                    .buttonStyle(.bordered).disabled(redoStack.isEmpty).keyboardShortcut("z", modifiers: [.command, .shift])
                Divider().frame(height: 38)
                Button { toggleStyle(\.bold) } label: { Label("Bold", systemImage: "bold").frame(minHeight: 42).padding(.horizontal, 9) }
                    .buttonStyle(.bordered).tint(selectedStyle.bold ? .accentColor : .primary)
                Button { toggleStyle(\.italic) } label: { Label("Italic", systemImage: "italic").frame(minHeight: 42).padding(.horizontal, 9) }
                    .buttonStyle(.bordered).tint(selectedStyle.italic ? .accentColor : .primary)
                Menu {
                    Button("No fill", systemImage: "xmark.circle") { setCellFill(nil) }
                    Button("Yellow", systemImage: "paintpalette") { setCellFill("yellow") }
                    Button("Blue", systemImage: "paintpalette") { setCellFill("blue") }
                    Button("Green", systemImage: "paintpalette") { setCellFill("green") }
                    Button("Red", systemImage: "paintpalette") { setCellFill("red") }
                } label: { Label("Fill", systemImage: "paintbucket").frame(minHeight: 42).padding(.horizontal, 9) }
                    .buttonStyle(.bordered)
                Menu {
                    Button("General", systemImage: "number") { setNumberFormat(nil) }
                    Button("Number", systemImage: "number") { setNumberFormat("number") }
                    Button("Currency", systemImage: "dollarsign") { setNumberFormat("currency") }
                    Button("Percentage", systemImage: "percent") { setNumberFormat("percentage") }
                } label: { Label(selectedStyle.numberFormat?.capitalized ?? "General", systemImage: "123").frame(minHeight: 42).padding(.horizontal, 9) }
                    .buttonStyle(.bordered)
                Menu {
                    Button("No borders", systemImage: "square") { setCellBorder(nil) }
                    Button("All borders", systemImage: "square.grid.3x3") { setCellBorder("all") }
                    Button("Bottom border", systemImage: "rectangle.bottomthird.inset.filled") { setCellBorder("bottom") }
                } label: { Label("Borders", systemImage: "square.dashed").frame(minHeight: 42).padding(.horizontal, 9) }
                    .buttonStyle(.bordered)
                Divider().frame(height: 38)
                ribbonCommand("Copy cell", icon: "doc.on.doc", action: copySelectedCell)
                ribbonCommand("Paste cells", icon: "clipboard", action: pasteCells)
                Divider().frame(height: 38)
                ribbonCommand("Insert row", icon: "plus", action: addRow)
                ribbonCommand("Insert column", icon: "rectangle.split.3x1", action: addColumn)
                Divider().frame(height: 38)
                ribbonCommand("Delete row", icon: "minus", action: deleteSelectedRow)
                ribbonCommand("Delete column", icon: "rectangle.split.3x1", action: deleteSelectedColumn)
                Spacer()
                Text("Cells").font(.caption).foregroundStyle(.secondary)
            }
        case .insert:
            HStack(spacing: 10) {
                ribbonCommand("Row above", icon: "arrow.up.to.line", action: insertRowAbove)
                ribbonCommand("Column before", icon: "arrow.left.to.line", action: insertColumnBefore)
                Menu {
                    Button("Column chart", systemImage: "chart.bar") { addChart(kind: "column") }
                    Button("Line chart", systemImage: "chart.xyaxis.line") { addChart(kind: "line") }
                } label: {
                    Label("Chart", systemImage: "chart.bar.xaxis")
                        .frame(minHeight: 42).padding(.horizontal, 9)
                }
                .buttonStyle(.bordered)
                Spacer()
                Text("Insert rows, columns, and charts from the selected data").font(.caption).foregroundStyle(.secondary)
            }
        case .formulas:
            HStack(spacing: 10) {
                ribbonCommand("Sum", icon: "sum", action: { insertAggregateAbove("SUM") })
                ribbonCommand("Average", icon: "divide", action: { insertAggregateAbove("AVERAGE") })
                ribbonCommand("Minimum", icon: "arrow.down.to.line", action: { insertAggregateAbove("MIN") })
                ribbonCommand("Maximum", icon: "arrow.up.to.line", action: { insertAggregateAbove("MAX") })
                Spacer()
                Text("Common formulas, ranges, and table lookups").font(.caption).foregroundStyle(.secondary)
            }
        case .data:
            HStack(spacing: 10) {
                ribbonCommand("Sort A to Z", icon: "arrow.up", action: { sortRows(ascending: true) })
                ribbonCommand("Sort Z to A", icon: "arrow.down", action: { sortRows(ascending: false) })
                Divider().frame(height: 38)
                Menu {
                    if activeFilter?.sheetID == activeSheet.id {
                        Button("Show all rows", systemImage: "line.3.horizontal.decrease.circle") { activeFilter = nil }
                        Divider()
                    }
                    ForEach(filterOptions) { option in
                        Button(option.title) {
                            activeFilter = GridColumnFilter(sheetID: activeSheet.id, column: selected.column, value: option.value)
                            if selected.row > 0, !rowMatchesFilter(selected.row) {
                                selected.row = visibleRows.first(where: { $0 > 0 }) ?? 0
                            }
                        }
                    }
                } label: {
                    Label(activeFilter?.sheetID == activeSheet.id ? "Filtered" : "Filter values", systemImage: "line.3.horizontal.decrease")
                        .frame(minHeight: 42).padding(.horizontal, 9)
                }
                .buttonStyle(.bordered)
                ribbonCommand("Open workbook", icon: "square.and.arrow.down", action: { activeImporter = true })
                ribbonCommand("Current sheet CSV", icon: "square.and.arrow.up", action: exportCSV)
                ribbonCommand("Export Excel", icon: "tablecells", action: exportXLSX)
                Spacer()
                Text("Sort/filter by selected column; row 1 stays as the header").font(.caption).foregroundStyle(.secondary)
            }
        case .view:
            HStack(spacing: 10) {
                Toggle(isOn: $showsGridlines) {
                    Label("Gridlines", systemImage: "tablecells")
                }
                .toggleStyle(.switch).fixedSize()
                Divider().frame(height: 38)
                Button { adjustZoom(by: -0.1) } label: { Label("Zoom out", systemImage: "minus.magnifyingglass") }
                    .buttonStyle(.bordered).disabled(zoom <= 0.75)
                Text("\(Int((zoom * 100).rounded()))%")
                    .font(.caption.monospacedDigit().weight(.semibold)).frame(minWidth: 42)
                Button { adjustZoom(by: 0.1) } label: { Label("Zoom in", systemImage: "plus.magnifyingglass") }
                    .buttonStyle(.bordered).disabled(zoom >= 1.5)
                Button("Reset") { zoom = 1 }.buttonStyle(.bordered).disabled(zoom == 1)
                Spacer()
                Text("\(workbook.sheets[activeSheetIndex].cells.count) rows x \(columnCount) columns")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func ribbonCommand(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(minHeight: 42)
                .padding(.horizontal, 9)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
    }

    private var formulaBar: some View {
        HStack(spacing: 12) {
            Text(selected.label)
                .font(.subheadline.monospaced().bold())
                .frame(width: 64)
                .padding(.vertical, 7)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 7))
            Image(systemName: "fx")
                .font(.subheadline.bold()).foregroundStyle(.secondary)
            TextField("Enter a value or =SUM(A1:A5)", text: selectedCellBinding)
                .textFieldStyle(.plain)
                .focused($formulaFocused)
                .submitLabel(.done)
            Spacer(minLength: 0)
            Text("Formula bar").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private var spreadsheetGrid: some View {
        GeometryReader { geometry in
        let formulaEngine = makeFormulaEngine(for: activeSheet)
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 0) {
                ForEach(workbook.charts.filter { $0.sheetID == activeSheet.id }) { chart in
                    GridChartCard(chart: chart, points: chartPoints(for: chart, formulaEngine: formulaEngine)) {
                        workbook.charts.removeAll { $0.id == chart.id }
                        exportURL = nil
                    }
                    .frame(width: max(320, geometry.size.width - 28))
                }
                HStack(spacing: 0) {
                    gridHeaderCell("", width: rowHeaderWidth)
                    ForEach(0..<columnCount, id: \.self) { column in
                        gridHeaderCell(Self.columnName(column), width: columnWidth)
                    }
                }
                ForEach(visibleRows, id: \.self) { row in
                    HStack(spacing: 0) {
                        gridHeaderCell(String(row + 1), width: rowHeaderWidth)
                        ForEach(activeSheet.cells[row].indices, id: \.self) { column in
                            let style = activeSheet.styles[GridAddress(row: row, column: column).label] ?? GridCellStyle()
                            let isSelected = selected.row == row && selected.column == column
                            let displayedValue = displayValue(row: row, column: column, formulaEngine: formulaEngine)
                            Button {
                                selected = GridAddress(row: row, column: column)
                                formulaFocused = false
                            } label: {
                                Text(displayedValue)
                                    .font(.system(size: 14 * zoomScale, weight: style.bold ? .bold : .regular, design: .rounded))
                                    .italic(style.italic)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 9 * zoomScale)
                                    .frame(width: columnWidth, height: 42 * zoomScale, alignment: .leading)
                                    .background(cellFill(style.fill, row: row))
                                    .overlay(isSelected ? Color.accentColor.opacity(0.13) : Color.clear)
                                    .overlay {
                                        if style.border == "all" { Rectangle().stroke(Color.primary.opacity(0.75), lineWidth: 1) }
                                    }
                                    .overlay(alignment: .bottom) {
                                        if style.border == "bottom" { Rectangle().fill(Color.primary.opacity(0.75)).frame(height: 1) }
                                    }
                                    .overlay {
                                        if (showsGridlines || isSelected) && style.border != "all" && style.border != "bottom" {
                                            Rectangle().stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: isSelected ? 1.5 : 0.5)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(Self.columnName(column))\(row + 1): \(displayedValue)")
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        }
    }

    private var sheetTabs: some View {
        HStack(spacing: 7) {
            Button { addSheet() } label: { Image(systemName: "plus").font(.system(size: 13, weight: .bold)).frame(width: 34, height: 32) }
                .buttonStyle(.bordered).accessibilityLabel("Add worksheet")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(workbook.sheets) { sheet in
                        Button { selectSheet(sheet.id) } label: {
                            Text(sheet.name).font(.subheadline.weight(sheet.id == selectedSheetID ? .semibold : .regular))
                                .padding(.horizontal, 13).frame(height: 32)
                                .background(sheet.id == selectedSheetID ? Color(uiColor: .systemBackground) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(sheet.id == selectedSheetID ? Color.accentColor.opacity(0.55) : Color.clear))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Rename sheet", systemImage: "pencil") { sheetNameDraft = sheet.name; selectedSheetID = sheet.id; showingRenameSheet = true }
                            if workbook.sheets.count > 1 {
                                Button("Delete sheet", systemImage: "trash", role: .destructive) { deleteSheet(sheet.id) }
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .alert("Rename worksheet", isPresented: $showingRenameSheet) {
            TextField("Worksheet name", text: $sheetNameDraft)
            Button("Cancel", role: .cancel) { }
            Button("Rename") { renameSheet() }
        } message: { Text("Names must be unique and no longer than 31 characters.") }
    }

    private var activeSheetIndex: Int { workbook.sheets.firstIndex(where: { $0.id == selectedSheetID }) ?? 0 }
    private var activeSheet: GridSheet { workbook.sheets[activeSheetIndex] }
    private var columnCount: Int { max(1, activeSheet.cells.first?.count ?? 1) }
    private var selectedStyle: GridCellStyle { activeSheet.styles[selected.label] ?? GridCellStyle() }
    private var filterOptions: [GridFilterOption] {
        guard activeSheet.cells.count > 1 else { return [] }
        var seen = Set<String>()
        var options: [GridFilterOption] = []
        let formulaEngine = makeFormulaEngine(for: activeSheet)
        for row in 1..<activeSheet.cells.count {
            let value = displayValue(row: row, column: selected.column, formulaEngine: formulaEngine)
            let key = value.isEmpty ? "blank" : "value:\(value)"
            if seen.insert(key).inserted { options.append(GridFilterOption(value: value.isEmpty ? nil : value)) }
            if options.count == 150 { break }
        }
        return options.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    private var visibleRows: [Int] {
        guard let filter = activeFilter, filter.sheetID == activeSheet.id else { return Array(activeSheet.cells.indices) }
        let formulaEngine = makeFormulaEngine(for: activeSheet)
        return activeSheet.cells.indices.filter { row in
            row == 0 || rowMatchesFilter(row, filter: filter, formulaEngine: formulaEngine)
        }
    }

    private func chartPoints(for chart: GridChart, formulaEngine: GridFormulaEngine) -> [GridChartPoint] {
        guard chart.sheetID == activeSheet.id,
              chart.categoryColumn >= 0,
              chart.valueColumn >= 0,
              activeSheet.cells.first?.indices.contains(chart.categoryColumn) == true,
              activeSheet.cells.first?.indices.contains(chart.valueColumn) == true,
              chart.firstDataRow <= chart.lastDataRow else { return [] }
        let lowerBound = max(0, chart.firstDataRow)
        let upperBound = min(chart.lastDataRow, activeSheet.cells.count - 1)
        guard lowerBound <= upperBound else { return [] }
        var points: [GridChartPoint] = []
        for row in lowerBound...upperBound {
            guard activeSheet.cells[row].indices.contains(chart.categoryColumn),
                  activeSheet.cells[row].indices.contains(chart.valueColumn),
                  let value = Double(formulaEngine.displayValue(row: row, column: chart.valueColumn)) else { continue }
            let category = displayValue(row: row, column: chart.categoryColumn, formulaEngine: formulaEngine)
            guard !category.isEmpty, value.isFinite else { continue }
            points.append(GridChartPoint(row: row, category: category, value: value))
        }
        return points
    }
    private var selectedCellBinding: Binding<String> {
        Binding(
            get: { value(at: selected.row, column: selected.column) },
            set: { setValue($0, at: selected.row, column: selected.column) }
        )
    }

    private func gridHeaderCell(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 12 * zoomScale, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, height: 34 * zoomScale)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .overlay(Rectangle().stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.5))
    }

    private func value(at row: Int, column: Int) -> String {
        guard workbook.sheets[activeSheetIndex].cells.indices.contains(row), workbook.sheets[activeSheetIndex].cells[row].indices.contains(column) else { return "" }
        return workbook.sheets[activeSheetIndex].cells[row][column]
    }

    private func makeFormulaEngine(for sheet: GridSheet) -> GridFormulaEngine {
        let formulaSheets = workbook.sheets.map { GridFormulaSheet(name: $0.name, cells: $0.cells) }
        return GridFormulaEngine(cells: sheet.cells, sheets: formulaSheets, currentSheetName: sheet.name)
    }

    private func rowMatchesFilter(_ row: Int, filter: GridColumnFilter? = nil, formulaEngine: GridFormulaEngine? = nil) -> Bool {
        guard let filter = filter ?? activeFilter, filter.sheetID == activeSheet.id else { return true }
        let displayed = displayValue(row: row, column: filter.column, formulaEngine: formulaEngine)
        return filter.value.map { displayed == $0 } ?? displayed.isEmpty
    }

    private func toggleStyle(_ keyPath: WritableKeyPath<GridCellStyle, Bool>) {
        var style = selectedStyle
        style[keyPath: keyPath].toggle()
        setCellStyle(style)
    }

    private func setCellFill(_ fill: String?) {
        var style = selectedStyle
        style.fill = fill
        setCellStyle(style)
    }

    private func setNumberFormat(_ format: String?) {
        var style = selectedStyle
        style.numberFormat = format
        setCellStyle(style)
    }

    private func setCellBorder(_ border: String?) {
        var style = selectedStyle
        style.border = border
        setCellStyle(style)
    }

    private func setCellStyle(_ style: GridCellStyle) {
        if style.isDefault { workbook.sheets[activeSheetIndex].styles.removeValue(forKey: selected.label) }
        else { workbook.sheets[activeSheetIndex].styles[selected.label] = style }
        exportURL = nil
    }

    private func cellFill(_ fill: String?, row: Int) -> Color {
        switch fill {
        case "yellow": return Color(red: 1.0, green: 0.96, blue: 0.67)
        case "blue": return Color(red: 0.72, green: 0.86, blue: 1.0)
        case "green": return Color(red: 0.73, green: 0.91, blue: 0.75)
        case "red": return Color(red: 1.0, green: 0.78, blue: 0.75)
        default: return row == 0 ? Color(uiColor: .secondarySystemGroupedBackground) : Color(uiColor: .systemBackground)
        }
    }

    private func remapStyles(_ transform: (Int, Int) -> (Int, Int)?) {
        var remapped: [String: GridCellStyle] = [:]
        for (label, style) in activeSheet.styles {
            guard let address = parseAddress(label), let destination = transform(address.row, address.column) else { continue }
            remapped[GridAddress(row: destination.0, column: destination.1).label] = style
        }
        workbook.sheets[activeSheetIndex].styles = remapped
    }

    private func parseAddress(_ label: String) -> GridAddress? {
        let letters = String(label.prefix { $0.isLetter }).uppercased()
        guard !letters.isEmpty, let row = Int(label.dropFirst(letters.count)), row > 0 else { return nil }
        let column = letters.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
        guard column >= 0 else { return nil }
        return GridAddress(row: row - 1, column: column)
    }

    private func setValue(_ text: String, at row: Int, column: Int) {
        guard workbook.sheets[activeSheetIndex].cells.indices.contains(row), workbook.sheets[activeSheetIndex].cells[row].indices.contains(column) else { return }
        workbook.sheets[activeSheetIndex].cells[row][column] = text
        exportURL = nil
        statusMessage = "Saving…"
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(workbook)
        isRestoringHistory = true
        workbook = previous
        normalizeSelection()
        statusMessage = "Undone"
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(workbook)
        isRestoringHistory = true
        workbook = next
        normalizeSelection()
        statusMessage = "Redone"
    }

    private func normalizeSelection() {
        if let firstSheet = workbook.sheets.first, !workbook.sheets.contains(where: { $0.id == selectedSheetID }) {
            selectedSheetID = firstSheet.id
        }
        let rows = workbook.sheets[activeSheetIndex].cells
        selected.row = min(max(selected.row, 0), max(rows.count - 1, 0))
        selected.column = min(max(selected.column, 0), max((rows.first?.count ?? 1) - 1, 0))
    }

    private func displayValue(row: Int, column: Int, formulaEngine: GridFormulaEngine? = nil) -> String {
        let raw = value(at: row, column: column)
        let value = raw.hasPrefix("=")
            ? (formulaEngine ?? makeFormulaEngine(for: activeSheet)).displayValue(row: row, column: column)
            : raw
        guard let number = Double(value),
              let format = activeSheet.styles[GridAddress(row: row, column: column).label]?.numberFormat else { return value }
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        switch format {
        case "number": formatter.numberStyle = .decimal
        case "currency": formatter.numberStyle = .currency
        case "percentage": formatter.numberStyle = .percent
        default: return value
        }
        return formatter.string(from: NSNumber(value: number)) ?? value
    }

    private func selectSheet(_ id: UUID) {
        selectedSheetID = id
        selected = GridAddress()
        formulaFocused = false
    }

    private func addSheet() {
        let name = nextSheetName()
        let sheet = GridSheet(name: name, cells: Array(repeating: Array(repeating: "", count: 12), count: 30))
        workbook.sheets.append(sheet)
        selectSheet(sheet.id)
    }

    private func nextSheetName() -> String {
        var number = 1
        while workbook.sheets.contains(where: { $0.name.lowercased() == "sheet\(number)" }) { number += 1 }
        return "Sheet\(number)"
    }

    private func renameSheet() {
        let trimmed = sheetNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = String(trimmed.filter { !"[]:*?/\\".contains($0) }.prefix(31))
        guard !cleaned.isEmpty,
              !workbook.sheets.enumerated().contains(where: { $0.offset != activeSheetIndex && $0.element.name.caseInsensitiveCompare(cleaned) == .orderedSame }) else {
            statusMessage = "Worksheet name is invalid or already used"
            return
        }
        workbook.sheets[activeSheetIndex].name = cleaned
    }

    private func deleteSheet(_ id: UUID) {
        guard workbook.sheets.count > 1, let index = workbook.sheets.firstIndex(where: { $0.id == id }) else { return }
        workbook.sheets.remove(at: index)
        workbook.charts.removeAll { $0.sheetID == id }
        if selectedSheetID == id { selectSheet(workbook.sheets[min(index, workbook.sheets.count - 1)].id) }
    }

    private func addRow() { workbook.sheets[activeSheetIndex].cells.append(Array(repeating: "", count: columnCount)) }
    private func addColumn() { for index in workbook.sheets[activeSheetIndex].cells.indices { workbook.sheets[activeSheetIndex].cells[index].append("") } }

    private func deleteSelectedRow() {
        guard workbook.sheets[activeSheetIndex].cells.count > 1 else {
            statusMessage = "A sheet must keep at least one row"
            return
        }
        let removedRow = selected.row
        remapStyles { row, column in row == removedRow ? nil : (row > removedRow ? row - 1 : row, column) }
        workbook.sheets[activeSheetIndex].cells.remove(at: selected.row)
        selected.row = min(selected.row, workbook.sheets[activeSheetIndex].cells.count - 1)
    }

    private func deleteSelectedColumn() {
        guard columnCount > 1 else {
            statusMessage = "A sheet must keep at least one column"
            return
        }
        let removedColumn = selected.column
        remapStyles { row, column in column == removedColumn ? nil : (row, column > removedColumn ? column - 1 : column) }
        for row in workbook.sheets[activeSheetIndex].cells.indices where workbook.sheets[activeSheetIndex].cells[row].indices.contains(selected.column) {
            workbook.sheets[activeSheetIndex].cells[row].remove(at: selected.column)
        }
        selected.column = min(selected.column, columnCount - 1)
    }

    private func adjustZoom(by amount: Double) {
        zoom = (min(1.5, max(0.75, zoom + amount)) * 10).rounded() / 10
    }

    private func sortRows(ascending: Bool) {
        let sheetIndex = activeSheetIndex
        let cells = workbook.sheets[sheetIndex].cells
        let valueRows = cells.indices.filter { row in cells[row].contains(where: { !$0.isEmpty }) }
        let styledRows = workbook.sheets[sheetIndex].styles.keys.compactMap { parseAddress($0)?.row }
        guard let lastUsedRow = (valueRows + styledRows).max(), lastUsedRow > 1 else {
            statusMessage = "Add a header row and at least two data rows before sorting"
            return
        }
        let formulaEngine = makeFormulaEngine(for: activeSheet)
        let rows = (1...lastUsedRow).map { sourceRow -> (source: Int, cells: [String], key: String) in
            let key = formulaEngine.displayValue(row: sourceRow, column: selected.column)
            return (sourceRow, cells[sourceRow], key)
        }
        let sortedRows = rows.sorted { left, right in
            let leftBlank = left.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let rightBlank = right.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if leftBlank != rightBlank { return !leftBlank }
            let comparison: ComparisonResult
            if let leftNumber = Double(left.key), let rightNumber = Double(right.key) {
                comparison = leftNumber == rightNumber ? .orderedSame : (leftNumber < rightNumber ? .orderedAscending : .orderedDescending)
            } else {
                comparison = left.key.localizedStandardCompare(right.key)
            }
            if comparison == .orderedSame { return left.source < right.source }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }

        var sourceToDestination: [Int: Int] = [:]
        var reorderedCells = cells
        for (offset, item) in sortedRows.enumerated() {
            let destinationRow = offset + 1
            sourceToDestination[item.source] = destinationRow
            reorderedCells[destinationRow] = item.cells.map { value in
                value.hasPrefix("=") ? translatedFormula(value, rowDelta: destinationRow - item.source, columnDelta: 0) : value
            }
        }
        workbook.sheets[sheetIndex].cells = reorderedCells

        var reorderedStyles: [String: GridCellStyle] = [:]
        for (label, style) in workbook.sheets[sheetIndex].styles {
            guard let address = parseAddress(label) else { continue }
            let row = sourceToDestination[address.row] ?? address.row
            reorderedStyles[GridAddress(row: row, column: address.column).label] = style
        }
        workbook.sheets[sheetIndex].styles = reorderedStyles
        if let destination = sourceToDestination[selected.row] { selected.row = destination }
        exportURL = nil
        statusMessage = ascending ? "Rows sorted A to Z" : "Rows sorted Z to A"
    }

    private func copySelectedCell() {
        let copiedValue = value(at: selected.row, column: selected.column)
        UIPasteboard.general.string = copiedValue
        copiedCell = GridClipboardCell(
            value: copiedValue,
            row: selected.row,
            column: selected.column,
            style: activeSheet.styles[selected.label] ?? GridCellStyle()
        )
        statusMessage = "Cell copied"
    }

    private func pasteCells() {
        let clipboard = UIPasteboard.general.string
        if let copiedCell, clipboard == nil || clipboard == copiedCell.value {
            let rowDelta = selected.row - copiedCell.row
            let columnDelta = selected.column - copiedCell.column
            let pastedValue = copiedCell.value.hasPrefix("=")
                ? translatedFormula(copiedCell.value, rowDelta: rowDelta, columnDelta: columnDelta)
                : copiedCell.value
            setValue(pastedValue, at: selected.row, column: selected.column)
            let sheetIndex = activeSheetIndex
            if copiedCell.style.isDefault { workbook.sheets[sheetIndex].styles.removeValue(forKey: selected.label) }
            else { workbook.sheets[sheetIndex].styles[selected.label] = copiedCell.style }
            exportURL = nil
            statusMessage = "Cell pasted"
            return
        }
        guard let clipboard, !clipboard.isEmpty else {
            statusMessage = "Clipboard is empty"
            return
        }
        let delimiter = clipboard.contains("\t") ? "\t" : ","
        let rows = parseDelimited(clipboard, delimiter: delimiter)
        guard !rows.isEmpty else { return }
        let sourceWidth = rows.map(\.count).max() ?? 1
        let targetRows = selected.row + rows.count
        let targetColumns = selected.column + sourceWidth
        guard targetRows <= 10_000, targetColumns <= 256 else {
            statusMessage = "Pasted range exceeds the worksheet limit"
            return
        }
        let sheetIndex = activeSheetIndex
        if workbook.sheets[sheetIndex].cells.count < targetRows {
            let width = max(columnCount, targetColumns)
            while workbook.sheets[sheetIndex].cells.count < targetRows {
                workbook.sheets[sheetIndex].cells.append(Array(repeating: "", count: width))
            }
        }
        for row in workbook.sheets[sheetIndex].cells.indices where workbook.sheets[sheetIndex].cells[row].count < targetColumns {
            let missing = targetColumns - workbook.sheets[sheetIndex].cells[row].count
            workbook.sheets[sheetIndex].cells[row].append(contentsOf: Array(repeating: "", count: missing))
        }
        for (rowOffset, rowValues) in rows.enumerated() {
            for (columnOffset, text) in rowValues.enumerated() {
                workbook.sheets[sheetIndex].cells[selected.row + rowOffset][selected.column + columnOffset] = text
            }
        }
        selected = GridAddress(row: targetRows - 1, column: targetColumns - 1)
        exportURL = nil
        statusMessage = "Pasted \(rows.count) rows × \(sourceWidth) columns"
    }

    private func insertRowAbove() {
        let insertionRow = selected.row
        remapStyles { row, column in (row >= insertionRow ? row + 1 : row, column) }
        workbook.sheets[activeSheetIndex].cells.insert(Array(repeating: "", count: columnCount), at: selected.row)
    }

    private func insertColumnBefore() {
        let insertionColumn = selected.column
        remapStyles { row, column in (row, column >= insertionColumn ? column + 1 : column) }
        for row in workbook.sheets[activeSheetIndex].cells.indices {
            let insertionIndex = min(selected.column, workbook.sheets[activeSheetIndex].cells[row].count)
            workbook.sheets[activeSheetIndex].cells[row].insert("", at: insertionIndex)
        }
    }

    private func insertAggregateAbove(_ function: String) {
        guard selected.row > 0 else {
            statusMessage = "Select a cell below the values to sum"
            return
        }
        let column = Self.columnName(selected.column)
        setValue("=\(function)(\(column)1:\(column)\(selected.row))", at: selected.row, column: selected.column)
    }

    private func addChart(kind: String) {
        guard workbook.charts.count < 500 else {
            statusMessage = "A workbook can contain up to 500 charts"
            return
        }
        guard columnCount > 1, activeSheet.cells.count > 1 else {
            statusMessage = "Add a category column and numeric data before inserting a chart"
            return
        }
        let valueColumn = selected.column == 0 ? 1 : min(selected.column, columnCount - 1)
        let lastRow = activeSheet.cells.indices.dropFirst().last { row in
            let category = activeSheet.cells[row].indices.contains(0) ? activeSheet.cells[row][0] : ""
            let value = activeSheet.cells[row].indices.contains(valueColumn) ? activeSheet.cells[row][valueColumn] : ""
            return !category.isEmpty || !value.isEmpty
        }
        guard let lastRow, lastRow > 0 else {
            statusMessage = "Enter chart categories and values below the header row"
            return
        }
        let formulaEngine = makeFormulaEngine(for: activeSheet)
        let firstHeader = activeSheet.cells[0].indices.contains(valueColumn) ? activeSheet.cells[0][valueColumn] : ""
        let title = firstHeader.isEmpty ? "\(Self.columnName(valueColumn)) values" : firstHeader
        let chart = GridChart(title: title, sheetID: activeSheet.id, categoryColumn: 0, valueColumn: valueColumn, firstDataRow: 1, lastDataRow: lastRow, kind: kind)
        guard !chartPoints(for: chart, formulaEngine: formulaEngine).isEmpty else {
            statusMessage = "The selected column has no numeric chart values"
            return
        }
        workbook.charts.append(chart)
        exportURL = nil
        selectedRibbonTab = .view
        statusMessage = "\(kind == "line" ? "Line" : "Column") chart added below the worksheet"
    }

    private func newWorkbook() {
        workbook = GridWorkbook()
        selectedSheetID = workbook.sheets[0].id
        selected = GridAddress()
        exportURL = nil
        persist(workbook)
    }

    private func persist(_ workbook: GridWorkbook) {
        if let index = savedWorkbooks.firstIndex(where: { $0.id == workbook.id }) {
            savedWorkbooks[index] = workbook
        } else {
            savedWorkbooks.insert(workbook, at: 0)
        }
        do {
            try FileManager.default.createDirectory(at: Self.libraryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(savedWorkbooks)
            try data.write(to: Self.libraryURL, options: .atomic)
        } catch {
            statusMessage = "Could not save spreadsheet"
            return
        }
        statusMessage = "All changes saved"
    }

    private func scheduleSave(_ updated: GridWorkbook) {
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            persist(updated)
        }
    }

    private func openWorkbook(_ id: UUID) {
        guard let saved = savedWorkbooks.first(where: { $0.id == id }) else { return }
        workbook = saved
        selectedSheetID = saved.sheets[0].id
        selected = GridAddress()
        exportURL = nil
    }

    private func exportCSV() {
        let csv = workbook.sheets[activeSheetIndex].cells.map { row in row.map(escapeCSV).joined(separator: ",") }.joined(separator: "\r\n")
        let name = safeFileName(workbook.title) + ".csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try Data(csv.utf8).write(to: url, options: .atomic); exportURL = url }
        catch { statusMessage = "Could not export CSV" }
    }

    private func importSpreadsheet(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let importedSheets: [GridSheet]
            let importedCharts: [GridXlsxChart]
            if url.pathExtension.lowercased() == "xlsx" {
                let imported = try GridXlsxCodec.decode(Data(contentsOf: url))
                importedSheets = imported.sheets.map { GridSheet(name: $0.sheetName, cells: normalized($0.cells), styles: $0.styles) }
                importedCharts = imported.charts
            } else {
                let text = try String(contentsOf: url, encoding: .utf8)
                importedSheets = [GridSheet(name: "Sheet1", cells: normalized(parseCSV(text)))]
                importedCharts = []
            }
            guard !importedSheets.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            workbook = GridWorkbook(title: url.deletingPathExtension().lastPathComponent, sheets: importedSheets)
            let sheetsByName = Dictionary(workbook.sheets.map { ($0.name, $0.id) }, uniquingKeysWith: { first, _ in first })
            workbook.charts = importedCharts.compactMap { chart in
                guard let sheetID = sheetsByName[chart.sheetName] else { return nil }
                return GridChart(title: chart.title, sheetID: sheetID, categoryColumn: chart.categoryColumn, valueColumn: chart.valueColumn, firstDataRow: chart.firstDataRow, lastDataRow: chart.lastDataRow, kind: chart.kind)
            }
            selectedSheetID = workbook.sheets[0].id
            selected = GridAddress()
            exportURL = nil
        } catch { statusMessage = "Could not open this spreadsheet" }
    }

    private func exportXLSX() {
        do {
            let data = try GridXlsxCodec.encode(title: workbook.title, sheets: workbook.sheets.map { sheet in
                let charts = workbook.charts.filter { $0.sheetID == sheet.id }.map {
                    GridXlsxChart(sheetName: sheet.name, title: $0.title, categoryColumn: $0.categoryColumn, valueColumn: $0.valueColumn, firstDataRow: $0.firstDataRow, lastDataRow: $0.lastDataRow, kind: $0.kind)
                }
                return GridXlsxSheet(sheetName: sheet.name, cells: sheet.cells, styles: sheet.styles, charts: charts)
            })
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeFileName(workbook.title) + ".xlsx")
            try data.write(to: url, options: .atomic)
            exportURL = url
            statusMessage = "Excel workbook ready to share"
        } catch {
            statusMessage = "Could not export this Excel workbook"
        }
    }

    private func normalized(_ rows: [[String]]) -> [[String]] {
        let source = rows.isEmpty ? [[]] : rows
        let width = max(1, source.map(\.count).max() ?? 1)
        return source.map { $0 + Array(repeating: "", count: width - $0.count) }
    }

    private func translatedFormula(_ formula: String, rowDelta: Int, columnDelta: Int) -> String {
        var output = ""
        var code = ""
        var isInsideString = false
        var index = formula.startIndex
        while index < formula.endIndex {
            let character = formula[index]
            if character == "\"" {
                let next = formula.index(after: index)
                if isInsideString, next < formula.endIndex, formula[next] == "\"" {
                    output.append(character)
                    output.append(character)
                    index = formula.index(index, offsetBy: 2)
                    continue
                }
                if isInsideString {
                    output.append(character)
                    isInsideString = false
                } else {
                    output += translateFormulaReferences(code, rowDelta: rowDelta, columnDelta: columnDelta)
                    code = ""
                    output.append(character)
                    isInsideString = true
                }
            } else if character == "'" && !isInsideString {
                output += translateFormulaReferences(code, rowDelta: rowDelta, columnDelta: columnDelta)
                code = ""
                output.append(character)
                index = formula.index(after: index)
                while index < formula.endIndex {
                    let quotedCharacter = formula[index]
                    output.append(quotedCharacter)
                    index = formula.index(after: index)
                    if quotedCharacter == "'" {
                        if index < formula.endIndex, formula[index] == "'" {
                            output.append(formula[index])
                            index = formula.index(after: index)
                        } else {
                            break
                        }
                    }
                }
                continue
            } else if isInsideString {
                output.append(character)
            } else {
                code.append(character)
            }
            index = formula.index(after: index)
        }
        output += isInsideString ? code : translateFormulaReferences(code, rowDelta: rowDelta, columnDelta: columnDelta)
        return output
    }

    private func translateFormulaReferences(_ code: String, rowDelta: Int, columnDelta: Int) -> String {
        let source = code as NSString
        guard let regex = try? NSRegularExpression(pattern: "(?<![A-Za-z0-9_.])(\\$?)([A-Za-z]{1,3})(\\$?)([1-9][0-9]*)(?![A-Za-z0-9_.])") else { return code }
        let matches = regex.matches(in: code, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return code }
        var result = ""
        var cursor = 0
        for match in matches {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let nextIndex = NSMaxRange(match.range)
            let isFunctionName = nextIndex < source.length && source.substring(with: NSRange(location: nextIndex, length: 1)) == "("
            let isSheetName = nextIndex < source.length && source.substring(with: NSRange(location: nextIndex, length: 1)) == "!"
            guard !isFunctionName, !isSheetName,
                  let row = Int(source.substring(with: match.range(at: 4))),
                  let column = columnIndex(source.substring(with: match.range(at: 2))) else {
                result += source.substring(with: match.range)
                cursor = nextIndex
                continue
            }
            let absoluteColumn = source.substring(with: match.range(at: 1)) == "$"
            let absoluteRow = source.substring(with: match.range(at: 3)) == "$"
            let targetColumn = absoluteColumn ? column : column + columnDelta
            let targetRow = absoluteRow ? row - 1 : row - 1 + rowDelta
            guard targetColumn >= 0, targetColumn < 16_384, targetRow >= 0, targetRow < 1_048_576 else {
                result += "#REF!"
                cursor = nextIndex
                continue
            }
            result += "\(absoluteColumn ? "$" : "")\(Self.columnName(targetColumn))\(absoluteRow ? "$" : "")\(targetRow + 1)"
            cursor = nextIndex
        }
        result += source.substring(from: cursor)
        return result
    }

    private func columnIndex(_ letters: String) -> Int? {
        let value = letters.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 }
        return value > 0 ? value - 1 : nil
    }

    private func escapeCSV(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func parseCSV(_ text: String) -> [[String]] {
        parseDelimited(text, delimiter: ",")
    }

    private func parseDelimited(_ text: String, delimiter: String) -> [[String]] {
        var rows: [[String]] = [[]]
        var field = ""
        var quoted = false
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted && index + 1 < characters.count && characters[index + 1] == "\"" {
                    field.append("\""); index += 1
                } else { quoted.toggle() }
            } else if String(character) == delimiter && !quoted {
                rows[rows.count - 1].append(field); field = ""
            } else if (character == "\n" || character == "\r") && !quoted {
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" { index += 1 }
                rows[rows.count - 1].append(field); field = ""; rows.append([])
            } else { field.append(character) }
            index += 1
        }
        rows[rows.count - 1].append(field)
        if rows.last?.allSatisfy(\.isEmpty) == true { rows.removeLast() }
        return rows
    }

    static func columnName(_ column: Int) -> String {
        var value = column + 1
        var result = ""
        while value > 0 {
            let remainder = (value - 1) % 26
            result = String(UnicodeScalar(UInt32(65 + remainder))!) + result
            value = (value - 1) / 26
        }
        return result
    }

    private static var libraryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ArtCraftOffice/GridCraft/library.json")
    }

    private static func loadLibrary() -> [GridWorkbook]? {
        guard let data = try? Data(contentsOf: libraryURL) else { return nil }
        return try? JSONDecoder().decode([GridWorkbook].self, from: data)
    }
}
