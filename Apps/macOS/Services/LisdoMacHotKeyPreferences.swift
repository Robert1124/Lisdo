import Carbon
import Foundation

enum LisdoMacHotKeyAction: String, CaseIterable {
    case quickCapture
    case selectedArea
}

struct LisdoMacHotKeyPreset: Identifiable, Hashable {
    let id: String
    let title: String
    let keyCode: UInt32?
    let modifiers: UInt32

    var hotKey: MacGlobalHotKey? {
        guard let keyCode else { return nil }
        return MacGlobalHotKey(keyCode: keyCode, modifiers: modifiers)
    }
}

enum LisdoMacHotKeyPreferences {
    static let quickCapturePresetDefaultsKey = "lisdo.mac.hotkey.quick-capture.preset"
    static let selectedAreaPresetDefaultsKey = "lisdo.mac.hotkey.selected-area.preset"

    static let defaultQuickCapturePresetId = "command-shift-space"
    static let defaultSelectedAreaPresetId = "command-shift-a"

    static let quickCapturePresets: [LisdoMacHotKeyPreset] = [
        LisdoMacHotKeyPreset(id: "command-shift-space", title: "Command-Shift-Space", keyCode: 49, modifiers: UInt32(cmdKey | shiftKey)),
        LisdoMacHotKeyPreset(id: "command-option-space", title: "Command-Option-Space", keyCode: 49, modifiers: UInt32(cmdKey | optionKey)),
        LisdoMacHotKeyPreset(id: "control-option-space", title: "Control-Option-Space", keyCode: 49, modifiers: UInt32(controlKey | optionKey)),
        LisdoMacHotKeyPreset(id: "off", title: "Off", keyCode: nil, modifiers: 0)
    ]

    static let selectedAreaPresets: [LisdoMacHotKeyPreset] = [
        LisdoMacHotKeyPreset(id: "command-shift-a", title: "Command-Shift-A", keyCode: 0, modifiers: UInt32(cmdKey | shiftKey)),
        LisdoMacHotKeyPreset(id: "command-option-a", title: "Command-Option-A", keyCode: 0, modifiers: UInt32(cmdKey | optionKey)),
        LisdoMacHotKeyPreset(id: "control-option-a", title: "Control-Option-A", keyCode: 0, modifiers: UInt32(controlKey | optionKey)),
        LisdoMacHotKeyPreset(id: "off", title: "Off", keyCode: nil, modifiers: 0)
    ]

    static func defaultsKey(for action: LisdoMacHotKeyAction) -> String {
        switch action {
        case .quickCapture:
            return quickCapturePresetDefaultsKey
        case .selectedArea:
            return selectedAreaPresetDefaultsKey
        }
    }

    static func presets(for action: LisdoMacHotKeyAction) -> [LisdoMacHotKeyPreset] {
        switch action {
        case .quickCapture:
            return quickCapturePresets
        case .selectedArea:
            return selectedAreaPresets
        }
    }

    static func defaultPresetId(for action: LisdoMacHotKeyAction) -> String {
        switch action {
        case .quickCapture:
            return defaultQuickCapturePresetId
        case .selectedArea:
            return defaultSelectedAreaPresetId
        }
    }

    static func preset(for action: LisdoMacHotKeyAction, defaults: UserDefaults = .standard) -> LisdoMacHotKeyPreset {
        let rawValue = defaults.string(forKey: defaultsKey(for: action)) ?? defaultPresetId(for: action)
        return presets(for: action).first { $0.id == rawValue }
            ?? presets(for: action).first { $0.id == defaultPresetId(for: action) }
            ?? LisdoMacHotKeyPreset(id: "off", title: "Off", keyCode: nil, modifiers: 0)
    }

    static func store(_ presetId: String, for action: LisdoMacHotKeyAction, defaults: UserDefaults = .standard) {
        defaults.set(presetId, forKey: defaultsKey(for: action))
    }
}
