import AppKit

/// AppKit entry point: a menu bar utility with a custom settings window, so it
/// does not use SwiftUI scenes (a `Settings { EmptyView() }` scene used to leave
/// an empty "Settings" window behind).
@main
struct AkkimMain {
    @MainActor private static let delegate = AppDelegate()

    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
