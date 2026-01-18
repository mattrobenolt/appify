import SwiftUI

@main
struct appifyApp: App {
  @NSApplicationDelegateAdaptor(AppifyAppDelegate.self) var appDelegate
  let ghostty: GhosttyRuntime
  let config: AppifyConfig

  init() {
    ghostty = GhosttyRuntime()
    config = AppifyConfig.load()
  }

  var body: some Scene {
    WindowGroup {
      ContentView(
        ghosttyVersion: ghostty.version,
        ghosttyApp: ghostty.app!,
        config: config
      )
    }
    .defaultSize(width: 800, height: 600)  // Force initial size
    .commands {
      CommandGroup(replacing: .newItem) {}  // Prevent cmd+N
    }
  }
}
