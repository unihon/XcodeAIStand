//
//  InputInterceptor.swift
//  XcodeAIStand
//

import AppKit
import CoreGraphics
import Foundation

class InputInterceptor {
  static let shared = InputInterceptor()

  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?

  private init() {}

  func start() {
    // Create an event tap to intercept keyboard events (keyDown)
    // We need .cgSessionEventTap or .cghidEventTap. .cghidEventTap captures at HID level.
    // .headInsertEventTap allows us to modify/suppress.

    // Mask for KeyDown
    let eventMask = (1 << CGEventType.keyDown.rawValue)

    guard
      let tap = CGEvent.tapCreate(
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(eventMask),
        callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
          if type == .keyDown {
            // Check if Tab Key (KeyCode 48)
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 48 {
              // Check if we have a visible suggestion
              if InputInterceptor.shouldInterceptTab() {
                // Accept suggestion
                // We must do this asynchronously or handle carefully to avoid blocking tap
                DispatchQueue.main.async {
                  SuggestionService.shared.acceptSuggestion()
                }
                // Suppress event
                return nil
              }
            }
          }
          return Unmanaged.passUnretained(event)
        },
        userInfo: nil
      )
    else {
      Logger.log("Failed to create event tap. Ensure 'Input Monitoring' permission.")
      return
    }

    self.eventTap = tap
    self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)

    Logger.log("InputInterceptor started.")
  }

  // Helper to determine if we should intercept
  private static func shouldInterceptTab() -> Bool {
    // Check if there is a suggestion currently shown
    return SuggestionService.shared.currentSuggestion != nil
  }
}
