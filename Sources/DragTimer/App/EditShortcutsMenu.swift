import AppKit

/// A menu-bar app shows no main menu, but AppKit still resolves Command-key
/// shortcuts through it. Without an Edit menu, Paste, Copy, Cut, Undo and
/// Select All do nothing in the app's text fields.
enum EditShortcutsMenu {
    static func make() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        let main = NSMenu(title: "Main Menu")
        // The first item of a main menu is always treated as the app menu.
        main.addItem(NSMenuItem(title: "Drag Timer", action: nil, keyEquivalent: ""))
        main.addItem(editItem)
        return main
    }
}
