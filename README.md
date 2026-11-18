# ArtCraft Office

An iPad-first office suite built with SwiftUI and UIKit. The current target is iPadOS 17 and the app is configured for iPad devices, including iPad (9th generation). The interface uses an Office desktop-inspired title bar, app tabs and touch-sized ribbons.

## Build on a Mac

1. Install Xcode and its iOS simulator runtimes.
2. Install XcodeGen (`brew install xcodegen`).
3. Open Terminal in `ArtCraftApp` and run `xcodegen generate`.
4. Open `ArtCraftOffice.xcodeproj` in Xcode.
5. Select an iPad simulator or a connected iPad, then build and run.

The project uses ZIPFoundation (MIT) for Office Open XML archives. A physical iPad build needs an Apple Development signing team configured in Xcode; Xcode will resolve the Swift package on first build.

## Current feature set

- **WordCraft:** rich-text editing, font and paragraph controls, paper size/orientation/margins, page breaks, lists, Undo/Redo, Find/Replace, local autosave, saved documents, basic DOCX and RTF import/export, and paginated PDF export. DOCX import and export transfer the supported paper size, orientation, and margin preset; export encodes page breaks as Word page-break runs. DOCX currently preserves paragraphs and common run formatting; complex tables, images, headers, footers, and tracked changes are not implemented.
- **GridCraft:** editable spreadsheet grid with adjustable 75–150% zoom, cell selection and formula bar, Undo/Redo with keyboard shortcuts, single-cell copy with in-app format and relative-reference transfer, tabular clipboard paste, bold/italic/fill, number/currency/percentage, all-side and bottom borders, single-series column and line charts linked to the selected value column and first-column categories (saved locally and transferred through XLSX), operator precedence, cell references/ranges and cross-sheet references, circular-reference detection, and common functions including `SUM`, `SUMPRODUCT`, `AVERAGE`, `MEDIAN`, `MIN`, `MAX`, `LARGE`, `SMALL`, `COUNT`, `COUNTA`, `COUNTBLANK`, `COUNTIF`, `COUNTIFS`, `SUMIF`, `SUMIFS`, `AVERAGEIF`, `AVERAGEIFS`, `IF`, `ROUND`, `INDEX`, `MATCH`, `VLOOKUP`, `HLOOKUP`, `XLOOKUP`, `TEXTJOIN`, `CONCAT`, `VALUE`, `SUBSTITUTE`, `SEARCH`, `FIND`, `REPLACE`, `PROPER`, `EXACT`, `ISNUMBER`, `ISTEXT`, `ISBLANK`, `ISERROR`, `ISLOGICAL`, `ISNONTEXT`, `CHAR`, `CODE`, and other text functions. Conditional functions support comparison criteria and `*`/`?` wildcards. The Data ribbon can sort rows A to Z or Z to A by the selected column and filter visible rows by a value in the selected column; both actions keep row 1 as the header. CSV and basic multi-worksheet XLSX import/export, multiple local workbooks, Home/Insert/Formulas/Data/View ribbon tabs, row/column insertion/deletion, and gridline control are included. Workbook sheets can be added, renamed, selected, deleted, autosaved, and transferred through XLSX. XLSX carries the supported cell formats; CSV exports the current sheet's displayed values only.
- **DeckCraft:** slide editing, up to four inserted pictures per slide from the iPad photo library, speaker notes with an in-show presenter notes panel and PPTX transfer, themes, add/duplicate/reorder/delete, local presentations, PDF export, basic PPTX import/export for slide titles, body text, multiple pictures per slide, speaker notes, and one of the built-in themes, and a full-screen slideshow with touch and keyboard navigation. Shapes, charts, transitions, animations, and complex layouts are not preserved yet.
- **PdfCraft:** PDF viewing, thumbnails, native text search, on-device Vision OCR for scanned pages with text search, page navigation, and searchable OCR PDF export, bookmarks, page reorder/delete/rotate, highlight/underline/note/typed-signature annotations, redaction marks from selectable text or OCR lines, filling existing text, choice, and checkbox form fields, merge, page/range export, print, password unlock, encrypted export with permission choices, flattened-copy export, and redacted rasterized copies.

Documents are stored in the app's Documents directory. XcodeGen enables Files app access to that directory.

## Remaining for Office-level compatibility

The app is not yet feature-for-feature compatible with Microsoft Office desktop. GridCraft still needs multi-series and advanced chart types, tables, pivot tools, and a much broader formula engine; DeckCraft still needs video/audio, shapes, charts, transitions, animations, and complex layout preservation. WordCraft still needs richer DOCX layout support, and PdfCraft still needs certificate-backed digital signatures and advanced PDF form authoring.

## Build validation

This workspace is edited on Windows and does not include Xcode or an iOS SDK. The Swift compiler available in this Windows environment crashes on startup, so no reliable Swift typecheck or iOS build is available here. Run XcodeGen, then build and verify the app, PDFKit behavior, and iPad layout on macOS.
