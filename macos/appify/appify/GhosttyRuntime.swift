import AppKit
import Foundation
import GhosttyKit

final class GhosttyRuntime {
  let version: String
  private(set) var app: ghostty_app_t?
  private var argvStorage: [UnsafeMutablePointer<CChar>] = []
  private var argvPointers: [UnsafeMutablePointer<CChar>?] = []

  init() {
    let argv = GhosttyRuntime.buildArgv()
    argvStorage = argv.storage
    argvPointers = argv.pointers
    let result = argvPointers.withUnsafeMutableBufferPointer { buffer in
      guard let baseAddress = buffer.baseAddress else { return Int32(1) }
      return ghostty_init(UInt(buffer.count), baseAddress)
    }
    guard result == GHOSTTY_SUCCESS else {
      fatalError("ghostty_init failed with code \(result)")
    }

    let info = ghostty_info()
    let versionPtr = UnsafeRawPointer(info.version).assumingMemoryBound(to: UInt8.self)
    let versionBytes = UnsafeBufferPointer(start: versionPtr, count: Int(info.version_len))
    version = String(decoding: versionBytes, as: UTF8.self)

    guard let config = ghostty_config_new() else {
      fatalError("ghostty_config_new failed")
    }
    ghostty_config_load_default_files(config)
    ghostty_config_load_cli_args(config)
    ghostty_config_load_recursive_files(config)
    if let configUrl = Bundle.main.url(forResource: "appify", withExtension: "ghostty") {
      configUrl.path.withCString { ghostty_config_load_file(config, $0) }
    }
    ghostty_config_finalize(config)

    if ProcessInfo.processInfo.environment["APPIFY_DEBUG_CONFIG"] == "1" {
      var bg = ghostty_config_color_s()
      let key = "background"
      key.withCString { keyPtr in
        _ = ghostty_config_get(config, &bg, keyPtr, UInt(strlen(keyPtr)))
      }
      NSLog(
        "appify config background = #%02X%02X%02X",
        bg.r, bg.g, bg.b
      )
    }

    var runtimeConfig = ghostty_runtime_config_s()
    runtimeConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
    runtimeConfig.supports_selection_clipboard = false
    runtimeConfig.wakeup_cb = Self.wakeupCallback
    runtimeConfig.action_cb = Self.actionCallback
    runtimeConfig.read_clipboard_cb = Self.readClipboardCallback
    runtimeConfig.confirm_read_clipboard_cb = Self.confirmReadClipboardCallback
    runtimeConfig.write_clipboard_cb = Self.writeClipboardCallback
    runtimeConfig.close_surface_cb = Self.closeSurfaceCallback

    guard let ghosttyApp = ghostty_app_new(&runtimeConfig, config) else {
      fatalError("ghostty_app_new failed")
    }

    app = ghosttyApp

    ghostty_config_free(config)
  }

  deinit {
    for ptr in argvStorage {
      ptr.deallocate()
    }
  }

  private func tick() {
    ghostty_app_tick(app!)
  }

  private static let wakeupCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = {
    userdata in
    guard let userdata else { return }
    let runtime = Unmanaged<GhosttyRuntime>.fromOpaque(userdata).takeUnretainedValue()
    DispatchQueue.main.async {
      runtime.tick()
    }
  }

  private static let actionCallback:
    @convention(c) (ghostty_app_t?, ghostty_target_s, ghostty_action_s) -> Bool = {
      _, target, action in
      switch action.tag {
      case GHOSTTY_ACTION_SET_TITLE:
        guard let surfaceView = GhosttyRuntime.surfaceView(from: target) else { return false }
        guard let titlePtr = action.action.set_title.title else { return false }
        let title = String(cString: titlePtr)
        DispatchQueue.main.async {
          surfaceView.setTitle(title)
        }
        return true
      case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
        guard let surfaceView = GhosttyRuntime.surfaceView(from: target) else { return false }
        DispatchQueue.main.async {
          surfaceView.requestClose()
        }
        return true

      default:
        return false
      }
    }

  private static let readClipboardCallback:
    @convention(c) (UnsafeMutableRawPointer?, ghostty_clipboard_e, UnsafeMutableRawPointer?) -> Void =
      { _, _, _ in
      }

  private static let confirmReadClipboardCallback:
    @convention(c) (
      UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafeMutableRawPointer?,
      ghostty_clipboard_request_e
    ) -> Void = { _, _, _, _ in
    }

  private static let writeClipboardCallback:
    @convention(c) (
      UnsafeMutableRawPointer?, ghostty_clipboard_e, UnsafePointer<ghostty_clipboard_content_s>?,
      Int, Bool
    ) -> Void = { _, _, _, _, _ in
    }

  private static let closeSurfaceCallback: @convention(c) (UnsafeMutableRawPointer?, Bool) -> Void =
    { _, _ in
      DispatchQueue.main.async {
        NSApp.terminate(nil)
      }
    }

  private static func surfaceView(from target: ghostty_target_s) -> GhosttySurfaceView? {
    guard target.tag == GHOSTTY_TARGET_SURFACE else { return nil }
    guard let surface = target.target.surface else { return nil }
    guard let userdata = ghostty_surface_userdata(surface) else { return nil }
    return Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
  }

  private static func buildArgv() -> (
    storage: [UnsafeMutablePointer<CChar>],
    pointers: [UnsafeMutablePointer<CChar>?]
  ) {
    var args: [String] = []
    if let executableName = Bundle.main.executableURL?.lastPathComponent {
      args.append(executableName)
    } else if let arg0 = CommandLine.arguments.first {
      args.append(arg0)
    } else {
      args.append("appify")
    }

    let storage = args.map { makeCString($0) }
    let pointers = storage.map { UnsafeMutablePointer<CChar>?($0) }
    return (storage, pointers)
  }

  private static func makeCString(_ string: String) -> UnsafeMutablePointer<CChar> {
    let utf8 = Array(string.utf8CString)
    let ptr = UnsafeMutablePointer<CChar>.allocate(capacity: utf8.count)
    utf8.withUnsafeBufferPointer { buffer in
      if let baseAddress = buffer.baseAddress {
        ptr.initialize(from: baseAddress, count: buffer.count)
      }
    }
    return ptr
  }
}
