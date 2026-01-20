import AppKit
import GhosttyKit
import SwiftUI

final class GhosttySurfaceView: NSView {
  private let app: ghostty_app_t
  private var surface: ghostty_surface_t?
  private let commandCString: [CChar]
  private let cwdCString: [CChar]?
  private let defaultTitle: String
  private let initialWindowSize: NSSize
  private let wantsCustomSize: Bool
  private let envVars: [ghostty_env_var_s]
  private let envKeyStorage: [[CChar]]
  private let envValueStorage: [[CChar]]
  private var keyTextAccumulator: [String]?
  private var markedText = NSMutableAttributedString()
  private var pendingTitle: String?
  private var trackingArea: NSTrackingArea?
  private var didApplyInitialSize = false

  init(app: ghostty_app_t, config: AppifyConfig) {
    self.app = app
    let command = config.resolvedCommand
    self.commandCString = Array(command.utf8CString)
    self.cwdCString = config.cwd.map { Array($0.utf8CString) }
    self.defaultTitle = config.resolvedTitle
    self.initialWindowSize = NSSize(
      width: config.resolvedWidth,
      height: config.resolvedHeight
    )
    self.wantsCustomSize = config.hasCustomSize

    let envPairs = config.envPairs
    var keyStorage: [[CChar]] = []
    var valueStorage: [[CChar]] = []
    keyStorage.reserveCapacity(envPairs.count)
    valueStorage.reserveCapacity(envPairs.count)
    for (key, value) in envPairs {
      keyStorage.append(Array(key.utf8CString))
      valueStorage.append(Array(value.utf8CString))
    }
    var vars: [ghostty_env_var_s] = []
    vars.reserveCapacity(envPairs.count)
    for i in 0..<envPairs.count {
      let keyPtr = keyStorage[i].withUnsafeBufferPointer { $0.baseAddress }
      let valuePtr = valueStorage[i].withUnsafeBufferPointer { $0.baseAddress }
      vars.append(ghostty_env_var_s(key: keyPtr, value: valuePtr))
    }
    self.envKeyStorage = keyStorage
    self.envValueStorage = valueStorage
    self.envVars = vars

    super.init(
      frame: NSRect(
        x: 0,
        y: 0,
        width: initialWindowSize.width,
        height: initialWindowSize.height
      ))
    createSurface()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  deinit {
    if let surface {
      ghostty_surface_free(surface)
    }
  }

  override var acceptsFirstResponder: Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    applyInitialWindowSizeIfNeeded()
    updateSurfaceSize()
    updateTrackingAreas()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    updateSurfaceSize()
  }

  override func layout() {
    super.layout()
    updateSurfaceSize()
  }

  override func becomeFirstResponder() -> Bool {
    let result = super.becomeFirstResponder()
    if result, let surface {
      ghostty_surface_set_focus(surface, true)
    }
    return result
  }

  override func resignFirstResponder() -> Bool {
    let result = super.resignFirstResponder()
    if result, let surface {
      ghostty_surface_set_focus(surface, false)
    }
    return result
  }

  override func updateTrackingAreas() {
    if let trackingArea {
      removeTrackingArea(trackingArea)
    }

    let options: NSTrackingArea.Options = [
      .activeInKeyWindow,
      .mouseMoved,
      .mouseEnteredAndExited,
      .inVisibleRect,
    ]
    let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseDown(with event: NSEvent) {
    guard let surface else { return }
    let mods = GhosttyInput.ghosttyMods(event.modifierFlags)
    ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
  }

  override func mouseUp(with event: NSEvent) {
    guard let surface else { return }
    let mods = GhosttyInput.ghosttyMods(event.modifierFlags)
    ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods)
  }

  override func rightMouseDown(with event: NSEvent) {
    guard let surface else {
      super.rightMouseDown(with: event)
      return
    }
    let mods = GhosttyInput.ghosttyMods(event.modifierFlags)
    if !ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, mods) {
      super.rightMouseDown(with: event)
    }
  }

  override func rightMouseUp(with event: NSEvent) {
    guard let surface else {
      super.rightMouseUp(with: event)
      return
    }
    let mods = GhosttyInput.ghosttyMods(event.modifierFlags)
    if !ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, mods) {
      super.rightMouseUp(with: event)
    }
  }

  override func otherMouseDown(with event: NSEvent) {
    guard let surface, event.buttonNumber == 2 else { return }
    let mods = GhosttyInput.ghosttyMods(event.modifierFlags)
    ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_MIDDLE, mods)
  }

  override func otherMouseUp(with event: NSEvent) {
    guard let surface, event.buttonNumber == 2 else { return }
    let mods = GhosttyInput.ghosttyMods(event.modifierFlags)
    ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_MIDDLE, mods)
  }

  override func mouseEntered(with event: NSEvent) {
    super.mouseEntered(with: event)
    sendMousePosition(event)
  }

  override func mouseExited(with event: NSEvent) {
    if NSEvent.pressedMouseButtons != 0 {
      return
    }
    guard let surface else { return }
    let mods = GhosttyInput.ghosttyMods(event.modifierFlags)
    ghostty_surface_mouse_pos(surface, -1, -1, mods)
  }

  override func mouseMoved(with event: NSEvent) {
    sendMousePosition(event)
  }

  override func mouseDragged(with event: NSEvent) {
    mouseMoved(with: event)
  }

  override func rightMouseDragged(with event: NSEvent) {
    mouseMoved(with: event)
  }

  override func otherMouseDragged(with event: NSEvent) {
    mouseMoved(with: event)
  }

  override func scrollWheel(with event: NSEvent) {
    guard let surface else { return }
    var x = event.scrollingDeltaX
    var y = event.scrollingDeltaY
    let precision = event.hasPreciseScrollingDeltas
    if precision {
      x *= 2
      y *= 2
    }
    let mods = scrollMods(for: event, precision: precision)
    ghostty_surface_mouse_scroll(surface, x, y, mods)
  }

  override func keyDown(with event: NSEvent) {
    guard let surface else {
      interpretKeyEvents([event])
      return
    }
    let translationModsGhostty = ghostty_surface_key_translation_mods(
      surface,
      GhosttyInput.ghosttyMods(event.modifierFlags)
    )
    let translationFlags = GhosttyInput.eventModifierFlags(mods: translationModsGhostty)
    var translationMods = event.modifierFlags
    for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
      if translationFlags.contains(flag) {
        translationMods.insert(flag)
      } else {
        translationMods.remove(flag)
      }
    }

    let translationEvent: NSEvent
    if translationMods == event.modifierFlags {
      translationEvent = event
    } else {
      translationEvent =
        NSEvent.keyEvent(
          with: event.type,
          location: event.locationInWindow,
          modifierFlags: translationMods,
          timestamp: event.timestamp,
          windowNumber: event.windowNumber,
          context: nil,
          characters: event.characters(byApplyingModifiers: translationMods) ?? "",
          charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
          isARepeat: event.isARepeat,
          keyCode: event.keyCode
        ) ?? event
    }

    let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

    keyTextAccumulator = []
    defer { keyTextAccumulator = nil }

    let markedTextBefore = markedText.length > 0

    interpretKeyEvents([translationEvent])

    syncPreedit(clearIfNeeded: markedTextBefore)

    if let list = keyTextAccumulator, !list.isEmpty {
      for text in list {
        _ = keyAction(action, event: event, translationEvent: translationEvent, text: text)
      }
    } else {
      _ = keyAction(
        action,
        event: event,
        translationEvent: translationEvent,
        text: translationEvent.ghosttyCharacters,
        composing: markedText.length > 0 || markedTextBefore
      )
    }
  }

  override func keyUp(with event: NSEvent) {
    _ = keyAction(GHOSTTY_ACTION_RELEASE, event: event)
  }

  override func flagsChanged(with event: NSEvent) {
    let mod: UInt32
    switch event.keyCode {
    case 0x39: mod = GHOSTTY_MODS_CAPS.rawValue
    case 0x38, 0x3C: mod = GHOSTTY_MODS_SHIFT.rawValue
    case 0x3B, 0x3E: mod = GHOSTTY_MODS_CTRL.rawValue
    case 0x3A, 0x3D: mod = GHOSTTY_MODS_ALT.rawValue
    case 0x37, 0x36: mod = GHOSTTY_MODS_SUPER.rawValue
    default: return
    }

    if hasMarkedText() { return }

    let mods = GhosttyInput.ghosttyMods(event.modifierFlags)
    var action = GHOSTTY_ACTION_RELEASE
    if mods.rawValue & mod != 0 {
      let sidePressed: Bool
      switch event.keyCode {
      case 0x3C:
        sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERSHIFTKEYMASK) != 0
      case 0x3E:
        sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERCTLKEYMASK) != 0
      case 0x3D:
        sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERALTKEYMASK) != 0
      case 0x36:
        sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERCMDKEYMASK) != 0
      default:
        sidePressed = true
      }

      if sidePressed {
        action = GHOSTTY_ACTION_PRESS
      }
    }

    _ = keyAction(action, event: event)
  }

  func setTitle(_ title: String) {
    pendingTitle = title
    if let window {
      window.title = title
    }
  }

  func requestClose() {
    if let surface {
      ghostty_surface_request_close(surface)
    }
  }

  private func createSurface() {
    var config = ghostty_surface_config_new()
    config.userdata = Unmanaged.passUnretained(self).toOpaque()
    config.platform_tag = GHOSTTY_PLATFORM_MACOS
    config.platform = ghostty_platform_u(
      macos: ghostty_platform_macos_s(
        nsview: Unmanaged.passUnretained(self).toOpaque()
      ))
    config.wait_after_command = false
    config.scale_factor = Double(
      window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0)

    commandCString.withUnsafeBufferPointer { commandBuf in
      config.command = commandBuf.baseAddress

      if let cwdCString {
        cwdCString.withUnsafeBufferPointer { cwdBuf in
          config.working_directory = cwdBuf.baseAddress
          createSurfaceWithEnv(&config)
        }
      } else {
        createSurfaceWithEnv(&config)
      }
    }
  }

  private func applyTitleIfNeeded() {
    if let title = pendingTitle {
      window?.title = title
      return
    }

    if window?.title.isEmpty ?? true {
      window?.title = defaultTitle
    }
  }

  private func updateSurfaceSize() {
    guard let surface else { return }

    let scale = Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0)
    ghostty_surface_set_content_scale(surface, scale, scale)

    let fbRect = convertToBacking(bounds)
    ghostty_surface_set_size(surface, UInt32(fbRect.width), UInt32(fbRect.height))
  }

  private func applyInitialWindowSizeIfNeeded() {
    guard wantsCustomSize, !didApplyInitialSize, let window else { return }
    window.isRestorable = false
    window.setFrameAutosaveName("")
    didApplyInitialSize = true
    DispatchQueue.main.async {
      let currentSize = window.contentLayoutRect.size
      if currentSize.width != self.initialWindowSize.width
        || currentSize.height != self.initialWindowSize.height
      {
        window.setContentSize(self.initialWindowSize)
      }
    }
  }

  private func keyAction(
    _ action: ghostty_input_action_e,
    event: NSEvent,
    translationEvent: NSEvent? = nil,
    text: String? = nil,
    composing: Bool = false
  ) -> Bool {
    guard let surface else { return false }

    var keyEvent = event.ghosttyKeyEvent(action, translationMods: translationEvent?.modifierFlags)
    keyEvent.composing = composing

    if let text, text.count > 0,
      let codepoint = text.utf8.first, codepoint >= 0x20
    {
      return text.withCString { ptr in
        keyEvent.text = ptr
        return ghostty_surface_key(surface, keyEvent)
      }
    }

    return ghostty_surface_key(surface, keyEvent)
  }

  private func sendMousePosition(_ event: NSEvent) {
    guard let surface else { return }
    let pos = convert(event.locationInWindow, from: nil)
    let mods = GhosttyInput.ghosttyMods(event.modifierFlags)
    ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y, mods)
  }

  private func scrollMods(for event: NSEvent, precision: Bool) -> ghostty_input_scroll_mods_t {
    var mods: Int32 = precision ? 0b0000_0001 : 0
    let momentum: Int32
    switch event.momentumPhase {
    case .began: momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_BEGAN.rawValue)
    case .stationary: momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_STATIONARY.rawValue)
    case .changed: momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_CHANGED.rawValue)
    case .ended: momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_ENDED.rawValue)
    case .cancelled: momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_CANCELLED.rawValue)
    case .mayBegin: momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN.rawValue)
    default: momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_NONE.rawValue)
    }
    mods |= momentum << 1
    return mods
  }

  private func syncPreedit(clearIfNeeded: Bool = true) {
    guard let surface else { return }

    if markedText.length > 0 {
      let str = markedText.string
      let len = str.utf8CString.count
      if len > 0 {
        str.withCString { ptr in
          ghostty_surface_preedit(surface, ptr, UInt(len - 1))
        }
      }
    } else if clearIfNeeded {
      ghostty_surface_preedit(surface, nil, 0)
    }
  }

  private func sendText(_ text: String) {
    guard let surface else { return }
    let len = text.utf8CString.count
    if len == 0 { return }
    text.withCString { ptr in
      ghostty_surface_text(surface, ptr, UInt(len - 1))
    }
  }

  private func createSurfaceWithEnv(_ config: inout ghostty_surface_config_s) {
    if envVars.isEmpty {
      surface = ghostty_surface_new(app, &config)
      return
    }

    envVars.withUnsafeBufferPointer { envBuf in
      config.env_vars = UnsafeMutablePointer(mutating: envBuf.baseAddress)
      config.env_var_count = envVars.count
      surface = ghostty_surface_new(app, &config)
    }
  }
}

struct GhosttySurfaceViewRepresentable: NSViewRepresentable {
  let app: ghostty_app_t
  let config: AppifyConfig

  func makeNSView(context: Context) -> GhosttySurfaceView {
    GhosttySurfaceView(app: app, config: config)
  }

  func updateNSView(_ nsView: GhosttySurfaceView, context: Context) {
  }
}

extension GhosttySurfaceView: NSTextInputClient {
  func hasMarkedText() -> Bool {
    markedText.length > 0
  }

  func markedRange() -> NSRange {
    guard markedText.length > 0 else { return NSRange() }
    return NSRange(location: 0, length: markedText.length)
  }

  func selectedRange() -> NSRange {
    guard let surface else { return NSRange() }
    var text = ghostty_text_s()
    guard ghostty_surface_read_selection(surface, &text) else { return NSRange() }
    defer { ghostty_surface_free_text(surface, &text) }
    return NSRange(location: Int(text.offset_start), length: Int(text.offset_len))
  }

  func setMarkedText(_ string: Any, selectedRange _: NSRange, replacementRange _: NSRange) {
    switch string {
    case let value as NSAttributedString:
      markedText = NSMutableAttributedString(attributedString: value)
    case let value as String:
      markedText = NSMutableAttributedString(string: value)
    default:
      return
    }

    if keyTextAccumulator == nil {
      syncPreedit()
    }
  }

  func unmarkText() {
    if markedText.length > 0 {
      markedText.mutableString.setString("")
      syncPreedit()
    }
  }

  func validAttributesForMarkedText() -> [NSAttributedString.Key] {
    []
  }

  func attributedSubstring(
    forProposedRange range: NSRange,
    actualRange _: NSRangePointer?
  ) -> NSAttributedString? {
    guard let surface else { return nil }
    guard range.length > 0 else { return nil }
    var text = ghostty_text_s()
    guard ghostty_surface_read_selection(surface, &text) else { return nil }
    defer { ghostty_surface_free_text(surface, &text) }
    return NSAttributedString(string: String(cString: text.text))
  }

  func characterIndex(for point: NSPoint) -> Int {
    0
  }

  func firstRect(forCharacterRange range: NSRange, actualRange _: NSRangePointer?) -> NSRect {
    guard let surface else {
      return NSMakeRect(frame.origin.x, frame.origin.y, 0, 0)
    }

    var x: Double = 0
    var y: Double = 0
    var width: Double = 0
    var height: Double = 0
    ghostty_surface_ime_point(surface, &x, &y, &width, &height)

    let viewRect = NSMakeRect(x, bounds.height - y, width, max(height, 1))
    let winRect = convert(viewRect, to: nil)
    guard let window else { return winRect }
    return window.convertToScreen(winRect)
  }

  func insertText(_ string: Any, replacementRange _: NSRange) {
    guard NSApp.currentEvent != nil else { return }
    guard surface != nil else { return }

    let chars: String
    switch string {
    case let value as NSAttributedString:
      chars = value.string
    case let value as String:
      chars = value
    default:
      return
    }

    unmarkText()

    if var accumulator = keyTextAccumulator {
      accumulator.append(chars)
      keyTextAccumulator = accumulator
      return
    }

    sendText(chars)
  }

  override func doCommand(by _: Selector) {
  }
}
