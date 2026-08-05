@main
struct LayoutContract {
    static func main() {
        let cases: [(Int, Int, Int)] = [
            (0, 0, 0),
            (1, 1, 1),
            (2, 1, 2),
            (3, 1, 3),
            (4, 2, 2),
            (5, 2, 3),
            (6, 2, 3),
            (7, 3, 3),
            (9, 3, 3),
            (16, 4, 4)
        ]

        for (count, expectedRows, expectedColumns) in cases {
            let actual = gridDimensions(count)
            precondition(
                actual.rows == expectedRows && actual.cols == expectedColumns,
                "gridDimensions(\(count)) returned \(actual), expected \(expectedRows)x\(expectedColumns)"
            )
        }

        let configured = TerminalEnvironment.configured(from: [
            "PATH": "/usr/bin",
            "TERM": "screen",
            "TMUX": "/tmp/tmux.sock,123,0",
            "TMUX_PANE": "%7"
        ])
        precondition(configured["TERM"] == "xterm-256color")
        precondition(configured["COLORTERM"] == "truecolor")
        precondition(configured["TMUX"] == nil && configured["TMUX_PANE"] == nil)

        print("Terminal contract passed (\(cases.count) layouts + tmux boundary)")
    }
}
