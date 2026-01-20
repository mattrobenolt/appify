import SwiftUI

@main
struct AppifyApp: App {
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
    .defaultSize(width: config.resolvedWidth, height: config.resolvedHeight)
    .commands {
      CommandGroup(replacing: .newItem) {}  // Prevent cmd+N
    }
  }
}
