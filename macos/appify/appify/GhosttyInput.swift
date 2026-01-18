import AppKit
import GhosttyKit

enum GhosttyInput {
  static func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
    var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue

    if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
    if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
    if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
    if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
    if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }

    let rawFlags = flags.rawValue
    if rawFlags & UInt(NX_DEVICERSHIFTKEYMASK) != 0 {
      mods |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue
    }
    if rawFlags & UInt(NX_DEVICERCTLKEYMASK) != 0 {
      mods |= GHOSTTY_MODS_CTRL_RIGHT.rawValue
    }
    if rawFlags & UInt(NX_DEVICERALTKEYMASK) != 0 {
      mods |= GHOSTTY_MODS_ALT_RIGHT.rawValue
    }
    if rawFlags & UInt(NX_DEVICERCMDKEYMASK) != 0 {
      mods |= GHOSTTY_MODS_SUPER_RIGHT.rawValue
    }

    return ghostty_input_mods_e(mods)
  }

  static func eventModifierFlags(mods: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
    var flags = NSEvent.ModifierFlags(rawValue: 0)
    if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { flags.insert(.shift) }
    if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { flags.insert(.control) }
    if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { flags.insert(.option) }
    if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { flags.insert(.command) }
    return flags
  }
}

extension NSEvent {
  func ghosttyKeyEvent(
    _ action: ghostty_input_action_e,
    translationMods: NSEvent.ModifierFlags? = nil
  ) -> ghostty_input_key_s {
    var keyEvent = ghostty_input_key_s()
    keyEvent.action = action
    keyEvent.keycode = UInt32(keyCode)
    keyEvent.text = nil
    keyEvent.composing = false

    keyEvent.mods = GhosttyInput.ghosttyMods(modifierFlags)
    keyEvent.consumed_mods = GhosttyInput.ghosttyMods(
      (translationMods ?? modifierFlags).subtracting([.control, .command])
    )

    keyEvent.unshifted_codepoint = 0
    if type == .keyDown || type == .keyUp {
      if let chars = characters(byApplyingModifiers: []),
        let codepoint = chars.unicodeScalars.first
      {
        keyEvent.unshifted_codepoint = codepoint.value
      }
    }

    return keyEvent
  }

  var ghosttyCharacters: String? {
    guard let characters else { return nil }

    if characters.count == 1,
      let scalar = characters.unicodeScalars.first
    {
      if scalar.value < 0x20 {
        return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
      }

      if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
        return nil
      }
    }

    return characters
  }
}
