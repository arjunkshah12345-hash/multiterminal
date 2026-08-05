import Foundation

// MARK: - Grid math

/// Determines rows/cols for a given pane count so the layout is as square / landscape
/// as possible while matching the user's described rules:
///   1 -> 1x1, 2 -> 1x2 (left|right), 3 -> 1x3 (left|middle|right),
///   4 -> 2x2, 5 -> 2x3, 6 -> 2x3, 7 -> 3x3, 9 -> 3x3, 16 -> 4x4, ...
/// Panes are placed left-to-right, top-to-bottom; the final row may be partial.
func gridDimensions(_ n: Int) -> (rows: Int, cols: Int) {
    guard n > 0 else { return (0, 0) }
    // Keep the first three panes in one row, then choose the smallest
    // square-ish column count. The old floor(sqrt(n)) calculation made seven
    // panes render as a cramped 2x4 grid instead of the expected 3x3.
    if n <= 3 { return (1, n) }
    let cols = max(2, Int(sqrt(Double(n)).rounded(.up)))
    let rows = Int((Double(n) / Double(cols)).rounded(.up))
    return (rows, cols)
}

// MARK: - Layout presets

/// How the terminal grid arranges its panes. Persisted in `Settings`.
/// - `auto`: balanced (default).
/// - `singleColumn`: vertical stack, top → bottom.
/// - `singleRow`: horizontal row, left → right.
/// - `grid`: square-ish grid (2×2, 3×3, …) for ≥4 panes.
/// - `twoTopOneBottom`: two panes across the top, one full-width pane below —
///   i.e. exactly "2 on top, 1 bottom".
enum Layout: String, CaseIterable, Codable {
    case auto
    case singleColumn
    case singleRow
    case grid
    case twoTopOneBottom

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .singleColumn: return "Stack"
        case .singleRow: return "Row"
        case .grid: return "Grid"
        case .twoTopOneBottom: return "2 + 1"
        }
    }
}

/// Rows/cols (and optional merged-cell spans) chosen by a `Layout` for a pane count.
struct GridLayout {
    let rows: Int
    let cols: Int
    /// For layouts that merge cells: pane index → (rowSpan, colSpan), where the pane
    /// occupies `rowSpan` rows and `colSpan` columns starting at its base cell.
    let spans: [Int: (rowSpan: Int, colSpan: Int)]?
}

extension Layout {
    /// Decide rows/cols (and optional cell spans) for `n` visible panes.
    func arrange(paneCount n: Int) -> GridLayout {
        guard n > 0 else { return GridLayout(rows: 0, cols: 0, spans: nil) }
        switch self {
        case .auto:
            let (r, c) = gridDimensions(n)
            return GridLayout(rows: r, cols: c, spans: nil)
        case .singleColumn:
            return GridLayout(rows: n, cols: 1, spans: nil)
        case .singleRow:
            return GridLayout(rows: 1, cols: n, spans: nil)
        case .grid:
            // Square-ish: choose the smallest column count whose square covers n.
            let cols = max(1, Int(sqrt(Double(n)).rounded(.up)))
            let rows = Int((Double(n) / Double(cols)).rounded(.up))
            return GridLayout(rows: rows, cols: cols, spans: nil)
        case .twoTopOneBottom:
            // Two panes across the top, one full-width below (the "2 on top, 1 bottom"
            // shape). Falls back gracefully for other pane counts.
            if n == 1 { return GridLayout(rows: 1, cols: 1, spans: nil) }
            if n == 2 { return GridLayout(rows: 1, cols: 2, spans: nil) }
            if n == 3 {
                // row0: pane0 | pane1    row1: pane2 (spans both columns)
                return GridLayout(rows: 2, cols: 2, spans: [2: (rowSpan: 1, colSpan: 2)])
            }
            // n >= 4: keep two columns; the trailing pane of the final row spans
            // the full width when it would otherwise sit alone.
            let cols = 2
            let rows = (n + cols - 1) / cols
            if n % cols == 1 {
                return GridLayout(rows: rows, cols: cols, spans: [n - 1: (rowSpan: 1, colSpan: cols)])
            }
            return GridLayout(rows: rows, cols: cols, spans: nil)
        }
    }
}

