import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A CSV export that is not built until the share sheet asks for it.
///
/// Both export buttons used to hang off a computed property read from `body`:
///
/// ```swift
/// .toolbar {
///     if let exportURL = trendsExportURL { ShareLink(item: exportURL) ... }
/// }
/// ```
///
/// which meant every SwiftUI layout pass serialised the entire visible range —
/// awake-event detection, fragmentation and all, for up to three years of
/// nights — and wrote the result to disk on the main thread. On the Trends tab
/// that ran on every range change, every store update and every scroll-induced
/// invalidation.
///
/// Holding the closure instead makes constructing the toolbar item free, and
/// moves the work to the one moment it is actually needed.
struct CSVExportDocument: Transferable {
    private let build: @Sendable () -> CSVExportFile

    init(_ build: @escaping @Sendable () -> CSVExportFile) {
        self.build = build
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { document in
            SentTransferredFile(try document.build().writeTemporaryFile())
        }
    }
}
