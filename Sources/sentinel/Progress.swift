import Darwin
import Engine
import Foundation

// Only emit in-place progress when stdout is an interactive terminal.
let stdoutIsTTY = isatty(STDOUT_FILENO) != 0

/// Erase the current terminal line and print `next` without a newline.
/// When stdout is not a TTY, does nothing — callers print a summary instead.
func updateProgress(_ current: inout String, index: Int, total: Int, path: String) {
    guard stdoutIsTTY else { return }
    // ESC[2K — erase entire line; \r — go to column 0
    let line = "[\(index)/\(total)] \(path.sanitizedForDisplay())"
    print("\u{1B}[2K\r\(line)", terminator: "")
    fflush(stdout)
    current = line
}

/// Clear the progress line and move to a fresh line, ready for normal output.
func finishProgress(_ current: String) {
    guard stdoutIsTTY, !current.isEmpty else { return }
    print("\u{1B}[2K\r", terminator: "")
    fflush(stdout)
}
