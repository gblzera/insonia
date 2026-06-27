import AppKit

// Ponto de entrada. Um app de menu bar puro: sem ícone no Dock.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
