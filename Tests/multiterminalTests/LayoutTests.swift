@testable import multiterminal

#if canImport(XCTest)
import XCTest

final class LayoutTests: XCTestCase {
    func testGridDimensionsKeepsSmallLayoutsReadable() {
        XCTAssertEqual(gridDimensions(1).rows, 1)
        XCTAssertEqual(gridDimensions(1).cols, 1)
        XCTAssertEqual(gridDimensions(2).rows, 1)
        XCTAssertEqual(gridDimensions(2).cols, 2)
        XCTAssertEqual(gridDimensions(3).rows, 1)
        XCTAssertEqual(gridDimensions(3).cols, 3)
        XCTAssertEqual(gridDimensions(4).rows, 2)
        XCTAssertEqual(gridDimensions(4).cols, 2)
    }

    func testGridDimensionsAvoidsAwkwardWideSevenPaneLayout() {
        XCTAssertEqual(gridDimensions(7).rows, 3)
        XCTAssertEqual(gridDimensions(7).cols, 3)
    }

    func testEmptyGridHasNoRowsOrColumns() {
        XCTAssertEqual(gridDimensions(0).rows, 0)
        XCTAssertEqual(gridDimensions(0).cols, 0)
    }

    func testTerminalEnvironmentStartsTmuxAtANewBoundary() {
        let configured = TerminalEnvironment.configured(from: [
            "PATH": "/usr/bin",
            "TERM": "screen",
            "TMUX": "/tmp/tmux.sock,123,0",
            "TMUX_PANE": "%7"
        ])

        XCTAssertEqual(configured["PATH"], "/usr/bin")
        XCTAssertEqual(configured["TERM"], "xterm-256color")
        XCTAssertEqual(configured["COLORTERM"], "truecolor")
        XCTAssertNil(configured["TMUX"])
        XCTAssertNil(configured["TMUX_PANE"])
    }
}
#else

/// The macOS Command Line Tools do not include XCTest. Keep the package buildable there;
/// `make verify` executes this same contract through `tools/verify_layout.swift`.
enum LayoutTests {
    static func run() {
        expect(gridDimensions(1).rows == 1 && gridDimensions(1).cols == 1)
        expect(gridDimensions(2).rows == 1 && gridDimensions(2).cols == 2)
        expect(gridDimensions(3).rows == 1 && gridDimensions(3).cols == 3)
        expect(gridDimensions(4).rows == 2 && gridDimensions(4).cols == 2)
        expect(gridDimensions(7).rows == 3 && gridDimensions(7).cols == 3)
        expect(gridDimensions(0).rows == 0 && gridDimensions(0).cols == 0)
    }

    private static func expect(_ condition: @autoclosure () -> Bool) {
        precondition(condition(), "Grid layout contract failed")
    }
}
#endif
