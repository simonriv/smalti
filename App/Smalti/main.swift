import AppKit

let app = NSApplication.shared
let delegate = SmaltiAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
