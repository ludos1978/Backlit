import Foundation
import Combine

/// Lightweight app-wide undo stack for display adjustments (⌘Z in the menu window).
///
/// Each control pushes a restore closure when an edit gesture begins (or right
/// before a programmatic change like a reset). `undo()` pops and runs the most
/// recent closure. Views holding local slider state observe `undoTick` and
/// re-sync themselves after an undo.
@MainActor
final class UndoService: ObservableObject, @unchecked Sendable {
    static let shared = UndoService()

    /// Incremented after every performed undo so views can re-load local state.
    @Published private(set) var undoTick: Int = 0

    private var stack: [() -> Void] = []
    private let maxDepth = 50

    private init() {}

    /// Pushes a closure that restores the state captured at call time.
    func push(_ restore: @escaping () -> Void) {
        stack.append(restore)
        if stack.count > maxDepth {
            stack.removeFirst(stack.count - maxDepth)
        }
    }

    /// Undoes the most recent change, if any.
    func undo() {
        guard let restore = stack.popLast() else { return }
        restore()
        undoTick += 1
    }
}
