import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct TunnelhuntTrayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var manager = TunnelManager()

    
    var body: some Scene {
        MenuBarExtra {
            TrayView(manager: manager)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: manager.isAnyTunnelActive ? "bolt.fill" : "bolt.slash.fill")
                if manager.activeTunnelsCount > 0 {
                    Text("\(manager.activeTunnelsCount)")
                        .font(.caption)
                        .bold()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
