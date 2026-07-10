import AppKit
import Darwin

#if DEBUG
if CommandLine.arguments.contains("--self-test") {
    exit(SelfCheck.run())
}
#endif

let application = NSApplication.shared
let appDelegate = AppDelegate()

application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
