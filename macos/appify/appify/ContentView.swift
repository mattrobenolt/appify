import GhosttyKit
import SwiftUI

struct ContentView: View {
  let ghosttyVersion: String
  let ghosttyApp: ghostty_app_t
  let config: AppifyConfig

  var body: some View {
    GhosttySurfaceViewRepresentable(app: ghosttyApp, config: config)
      .frame(minWidth: 400, minHeight: 300)
  }
}
