//
//  SuggestionOverlay.swift
//  XcodeAIStand
//

import AppKit
import Combine

class SuggestionWindow: NSPanel {
  init() {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 30),  // Start with reasonable size
      styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
      backing: .buffered,
      defer: false
    )

    // Ghost text styling - subtle transparent background
    self.backgroundColor = NSColor.black.withAlphaComponent(0.7)
    self.isOpaque = false
    self.hasShadow = true
    self.level = .floating
    self.ignoresMouseEvents = true
    self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    self.hidesOnDeactivate = false
  }
}

class SuggestionWidgetController {
  static let shared = SuggestionWidgetController()

  private let window: SuggestionWindow
  private let label: NSTextField
  private var cancellables = Set<AnyCancellable>()

  private init() {
    Logger.log("[SuggestionWidget] Initializing...")

    // Ensure NSApplication is properly set up for a CLI app to show windows
    let _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)  // Allow windows without being a full app

    self.window = SuggestionWindow()

    self.label = NSTextField(labelWithString: "")
    self.label.textColor = NSColor.white.withAlphaComponent(0.8)
    self.label.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    self.label.drawsBackground = false
    self.label.isBordered = false

    self.window.contentView = self.label

    setupBindings()
    Logger.log("[SuggestionWidget] Initialized and bindings set up")
  }

  private func setupBindings() {
    SuggestionService.shared.$currentSuggestion
      .receive(on: RunLoop.main)
      .sink { [weak self] suggestion in
        if let text = suggestion, !text.isEmpty {
          self?.show(text: text)
        } else {
          self?.hide()
        }
      }
      .store(in: &cancellables)
  }

  func show(text: String) {
    Logger.log("[SuggestionWidget] Attempting to show suggestion: \(text.prefix(30))...")

    // We need to calculate where to show it.
    // For now, let's just get the cursor position from XcodeMonitor
    // NOTE: Precise positioning requires `kAXBoundsForRangeParameterizedAttribute` which is tricky.
    // We will try to get it via XcodeMonitor helper or implement it here.

    guard let cursorRect = getCursorRect() else {
      Logger.log("[SuggestionWidget] ERROR: Could not get cursor rect, cannot show suggestion")
      // Fallback or retry
      return
    }

    Logger.log("[SuggestionWidget] Cursor rect: \(cursorRect)")

    // Update font to match Xcode if possible (hard without reading Xcode's prefs, but we can guess or use system mono)
    // Typically San Francisco Mono or Menlo.
    self.label.font =
      NSFont(name: "SF Mono", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    self.label.stringValue = text
    self.label.sizeToFit()

    // Position:
    // cursorRect is usually the vertical line of the cursor.
    // We want to draw AFTER the cursor.
    let point = NSPoint(x: cursorRect.origin.x + 2, y: cursorRect.origin.y)  // Slight offset

    // Convert screen coordinates if needed. AX coordinates are screen coordinates (top-left origin).
    // NSWindow coordinates are bottom-left origin.
    // We need to flip Y.
    if let screen = NSScreen.main {
      // AX gives (x, y) where 0,0 is top-left of primary screen.
      // Cocoa window frame: 0,0 is bottom-left of primary screen.
      // We want to align with the bottom of the cursor rect.

      let cocoaBottomY = screen.frame.height - (cursorRect.origin.y + cursorRect.height)
      self.window.setFrameOrigin(NSPoint(x: point.x, y: cocoaBottomY))
      Logger.log("[SuggestionWidget] Window positioned at (\(point.x), \(cocoaBottomY))")
    }

    self.window.orderFront(nil)
    Logger.log("[SuggestionWidget] Window shown")
  }

  func hide() {
    self.window.orderOut(nil)
  }

  private func getCursorRect() -> CGRect? {
    // Ask XcodeMonitor for the cursor rect
    return XcodeMonitor.shared.getCursorBounds()
  }
}
