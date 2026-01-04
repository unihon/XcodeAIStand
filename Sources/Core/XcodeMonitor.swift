//
//  XcodeMonitor.swift
//  XcodeAIStand
//

import AppKit
import ApplicationServices
import Foundation

class XcodeMonitor {
  static let shared = XcodeMonitor()

  private var xcodeApp: AXUIElement?
  private var xcodeProcess: NSRunningApplication?

  private init() {}

  private var completionEnabled = false

  func start(enableCompletion: Bool = false) {
    Logger.log("[XcodeMonitor] Starting...")
    self.completionEnabled = enableCompletion

    // Find Xcode
    findXcode()

    // Monitor app activations
    NSWorkspace.shared.notificationCenter.addObserver(
      self,
      selector: #selector(appActivated(_:)),
      name: NSWorkspace.didActivateApplicationNotification,
      object: nil
    )
  }

  @objc private func appActivated(_ notification: Notification) {
    guard
      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    else {
      return
    }
    if app.bundleIdentifier == "com.apple.dt.Xcode" {
      findXcode()
    }
  }

  private func findXcode() {
    guard
      let xcode = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == "com.apple.dt.Xcode"
      })
    else {
      Logger.log("[XcodeMonitor] Xcode not found running")
      return
    }

    Logger.log("[XcodeMonitor] Found Xcode with PID: \(xcode.processIdentifier)")
    xcodeProcess = xcode
    xcodeApp = AXUIElementCreateApplication(xcode.processIdentifier)
    xcodeApp?.setTimeout(2.0)
    setupObserver(for: xcodeProcess?.processIdentifier)
  }

  // MARK: - Observer Logic

  private var axObserver: AXObserver?

  private func setupObserver(for pid: pid_t?) {
    guard let pid = pid else { return }

    var observer: AXObserver?
    guard
      AXObserverCreate(
        pid,
        { (observer, element, notification, refcon) in
          // Static C callback -> forward to Swift instance
          guard let refcon = refcon else { return }
          let monitor = Unmanaged<XcodeMonitor>.fromOpaque(refcon).takeUnretainedValue()
          monitor.handleNotification(notification: notification as String, element: element)
        }, &observer) == .success, let axObserver = observer
    else {
      Logger.log("Failed to create AXObserver")
      return
    }

    self.axObserver = axObserver
    let selfPtr = Unmanaged.passUnretained(self).toOpaque()

    // Add notification listeners to the application element
    // We listen to the application for window creation/focus, and specifically focus changes
    // But for text changes, we usually need to observe the *focused element*.
    // However, observing the app for "kAXFocusedUIElementChangedNotification" allows us to track the active editor.
    AXObserverAddNotification(
      axObserver, xcodeApp!, kAXFocusedUIElementChangedNotification as CFString, selfPtr)
    AXObserverAddNotification(
      axObserver, xcodeApp!, kAXApplicationActivatedNotification as CFString, selfPtr)
    AXObserverAddNotification(
      axObserver, xcodeApp!, kAXMainWindowChangedNotification as CFString, selfPtr)

    // Start run loop source
    CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(axObserver), .defaultMode)
    Logger.log("[XcodeMonitor] AXObserver setup complete for Xcode PID: \(pid)")

    // Initial check
    updateFocusedElementObserver()

    // Start polling as fallback (Xcode doesn't reliably send kAXValueChangedNotification)
    startPolling()
  }

  // MARK: - Polling Fallback

  private var pollingTimer: Timer?
  private var lastContentHash: Int = 0
  private var lastCursorPosition: Int = 0

  private func startPolling() {
    // Stop existing timer if any
    pollingTimer?.invalidate()

    // Poll every 200ms for changes
    pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
      self?.pollForChanges()
    }
    Logger.log("[XcodeMonitor] Polling started (200ms interval)")
  }

  private func pollForChanges() {
    guard let app = xcodeApp, let editor = app.focusedElement, editor.isTextArea else {
      return
    }

    let content = editor.stringValue
    let contentHash = content.hashValue

    // Get cursor position
    var cursorPos = 0
    if let range = editor.selectedTextRange {
      cursorPos = range.lowerBound
    }

    // Check if content or cursor changed
    if contentHash != lastContentHash || cursorPos != lastCursorPosition {
      lastContentHash = contentHash
      lastCursorPosition = cursorPos

      // Calculate current line info
      let beforeCursor = String(content.prefix(cursorPos))
      let lines = beforeCursor.components(separatedBy: "\n")
      let currentLine = lines.count
      let currentLineContent = lines.last ?? ""

      Logger.log(
        "[XcodeMonitor] Change detected at line \(currentLine): \(currentLineContent.prefix(50))..."
      )

      handleContentChange()
    }
  }

  private func handleContentChange() {
    // Only process for code completion if enabled
    guard completionEnabled else { return }

    let info = getFileInfo(includeSnippets: true)

    if let prev = info["previousSnippet"] as? String,
      let next = info["nextSnippet"] as? String
    {
      Logger.log(
        "[XcodeMonitor] Content change detected. Prefix: \(prev.count) chars, Suffix: \(next.count) chars"
      )
      SuggestionService.shared.onContentChanged(prefix: prev, suffix: next)
    } else {
      Logger.log("[XcodeMonitor] Could not get snippets from editor")
      SuggestionService.shared.dismissSuggestion()
    }
  }

  private var currentEditorElement: AXUIElement?

  private func updateFocusedElementObserver() {
    guard let app = xcodeApp, let element = app.focusedElement else { return }

    // If it's a new element, remove old observers and add new ones
    if element != currentEditorElement {
      if let old = currentEditorElement, let observer = axObserver {
        AXObserverRemoveNotification(observer, old, kAXValueChangedNotification as CFString)
        AXObserverRemoveNotification(observer, old, kAXSelectedTextChangedNotification as CFString)
      }

      currentEditorElement = element

      // Only observe if it is a text area (editor)
      if element.isTextArea, let observer = axObserver {
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(
          observer, element, kAXValueChangedNotification as CFString, selfPtr)
        AXObserverAddNotification(
          observer, element, kAXSelectedTextChangedNotification as CFString, selfPtr)
        Logger.log("[XcodeMonitor] Now observing text area for changes")

        // Trigger immediately for the new editor
        handleContentChange()
      } else {
        Logger.log("[XcodeMonitor] Focused element is NOT a text area, role: \(element.role)")
      }
    }
  }

  private func handleNotification(notification: String, element: AXUIElement) {
    Logger.log("[XcodeMonitor] Received notification: \(notification)")
    switch notification {
    case kAXFocusedUIElementChangedNotification:
      updateFocusedElementObserver()
    case kAXValueChangedNotification, kAXSelectedTextChangedNotification:
      handleContentChange()
    default:
      Logger.log("[XcodeMonitor] Unhandled notification: \(notification)")
    }
  }

  func getFileInfo(includeSnippets: Bool = false) -> [String: Any] {
    var result: [String: Any] = [:]

    // Ensure we have Xcode
    if xcodeApp == nil {
      findXcode()
    }

    guard let app = xcodeApp else {
      result["error"] = "Xcode not running"
      return result
    }

    // Get window
    guard let window = app.focusedWindow ?? app.windows.first else {
      result["error"] = "No Xcode window"
      return result
    }

    // Get document path
    if let docPath = window.document {
      let url = URL(fileURLWithPath: docPath.replacingOccurrences(of: "file://", with: ""))
      result["filePath"] = url.path
    }

    // Get focused element (text editor)
    if let editor = app.focusedElement, editor.isTextArea {
      // Get selected text range for cursor position
      if let range = editor.selectedTextRange {
        let content = editor.stringValue
        let cursorPos = range.lowerBound

        // Calculate line and column
        let beforeCursor = String(content.prefix(cursorPos))
        let lines = beforeCursor.components(separatedBy: "\n")

        result["cursorLine"] = lines.count
        result["cursorColumn"] = (lines.last?.count ?? 0) + 1
      }

      // Get selected text if any
      // Build context info
      if let range = editor.selectedTextRange {
        let content = editor.stringValue
        let lower = range.lowerBound
        let upper = range.upperBound
        let isSelection = lower < upper

        if isSelection {
          // Selection Case
          // 1. Selected text - now only returned when includeSnippets is true
          let selectedText = String(
            content[
              content.index(
                content.startIndex, offsetBy: lower)..<content.index(
                  content.startIndex, offsetBy: upper)])

          // Calculate selection start line and column
          let beforeSelectionStart = String(content.prefix(lower))
          let linesBeforeStart = beforeSelectionStart.components(separatedBy: "\n")
          let selectionStartLine = linesBeforeStart.count
          let selectionStartColumn = (linesBeforeStart.last?.count ?? 0) + 1

          // Calculate selection end line and column
          let beforeSelectionEnd = String(content.prefix(upper))
          let linesBeforeEnd = beforeSelectionEnd.components(separatedBy: "\n")
          let selectionEndLine = linesBeforeEnd.count
          let selectionEndColumn = (linesBeforeEnd.last?.count ?? 0) + 1

          result["selectionStartLine"] = selectionStartLine
          result["selectionStartColumn"] = selectionStartColumn
          result["selectionEndLine"] = selectionEndLine
          result["selectionEndColumn"] = selectionEndColumn

          if includeSnippets {
            result["selectedText"] = selectedText

            // 2. Previous context (100 chars)
            let startOffset = max(0, lower - 100)
            let prevStartIndex = content.index(content.startIndex, offsetBy: startOffset)
            let prevEndIndex = content.index(content.startIndex, offsetBy: lower)
            result["previousSnippet"] = String(content[prevStartIndex..<prevEndIndex])

            // 3. Next context (100 chars)
            let endOffset = min(content.count, upper + 100)
            let nextStartIndex = content.index(content.startIndex, offsetBy: upper)
            let nextEndIndex = content.index(content.startIndex, offsetBy: endOffset)
            result["nextSnippet"] = String(content[nextStartIndex..<nextEndIndex])
          }

        } else {
          // Cursor Case - no selection range info needed, cursor position is enough
          if includeSnippets {
            // 1. Previous context (200 chars)
            let startOffset = max(0, lower - 200)
            let prevStartIndex = content.index(content.startIndex, offsetBy: startOffset)
            let prevEndIndex = content.index(content.startIndex, offsetBy: lower)
            result["previousSnippet"] = String(content[prevStartIndex..<prevEndIndex])

            // 2. Next context (200 chars)
            let endOffset = min(content.count, lower + 200)
            let nextStartIndex = content.index(content.startIndex, offsetBy: lower)
            let nextEndIndex = content.index(content.startIndex, offsetBy: endOffset)
            result["nextSnippet"] = String(content[nextStartIndex..<nextEndIndex])
          }
        }
      }
    }

    return result
  }

  func getProjectRoot() -> String? {
    let fileInfo = getFileInfo()
    guard let filePath = fileInfo["filePath"] as? String else {
      return nil
    }

    var currentURL = URL(fileURLWithPath: filePath).deletingLastPathComponent()
    let fileManager = FileManager.default

    // Safety limit to avoid infinite loop
    for _ in 0..<20 {
      if currentURL.path == "/" { break }

      let path = currentURL.path

      // Check for common project markers
      let markers = [".git", "Package.swift", ".xcodeproj", ".xcworkspace", ".idea", ".vscode"]
      for marker in markers {
        var isDir: ObjCBool = false
        if fileManager.fileExists(
          atPath: currentURL.appendingPathComponent(marker).path, isDirectory: &isDir)
        {
          return path  // Found root
        }
      }

      currentURL = currentURL.deletingLastPathComponent()
    }

    return nil
  }

  func getCursorBounds() -> CGRect? {
    guard let app = xcodeApp, let editor = app.focusedElement else { return nil }

    // Get selected text range as AXValue
    guard let rangeVal: AXValue = editor.getValue(for: kAXSelectedTextRangeAttribute) else {
      return nil
    }

    var boundsValue: CFTypeRef?
    let result = AXUIElementCopyParameterizedAttributeValue(
      editor,
      kAXBoundsForRangeParameterizedAttribute as CFString,
      rangeVal,
      &boundsValue
    )

    if result == .success, let boundsSimple = boundsValue {
      if CFGetTypeID(boundsSimple) == AXValueGetTypeID() {
        let axVal = boundsSimple as! AXValue
        var rect = CGRect.zero
        if AXValueGetValue(axVal, .cgRect, &rect) {
          return rect
        }
      }
    }

    return nil
  }

  func insertText(_ text: String) {
    guard let app = xcodeApp, let editor = app.focusedElement else { return }

    // We can try setting kAXSelectedTextAttribute
    // This replaces the current selection (cursor or range) with the new text.
    // If it's a cursor, it inserts.

    let value = text as CFTypeRef
    AXUIElementSetAttributeValue(editor, kAXSelectedTextAttribute as CFString, value)
  }
}

// MARK: - AXUIElement Extensions

extension AXUIElement {
  func setTimeout(_ timeout: Float) {
    AXUIElementSetMessagingTimeout(self, timeout)
  }

  func getValue<T>(for attribute: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else {
      return nil
    }
    return value as? T
  }

  var focusedWindow: AXUIElement? {
    getValue(for: kAXFocusedWindowAttribute)
  }

  var windows: [AXUIElement] {
    getValue(for: kAXWindowsAttribute) ?? []
  }

  var focusedElement: AXUIElement? {
    getValue(for: kAXFocusedUIElementAttribute)
  }

  var document: String? {
    getValue(for: kAXDocumentAttribute)
  }

  var role: String {
    getValue(for: kAXRoleAttribute) ?? ""
  }

  var isTextArea: Bool {
    role == kAXTextAreaRole as String
  }

  var stringValue: String {
    getValue(for: kAXValueAttribute) ?? ""
  }

  var selectedText: String? {
    getValue(for: kAXSelectedTextAttribute)
  }

  var selectedTextRange: ClosedRange<Int>? {
    guard let axValue: AXValue = getValue(for: kAXSelectedTextRangeAttribute) else {
      return nil
    }
    var range = CFRange()
    guard AXValueGetValue(axValue, .cfRange, &range) else {
      return nil
    }
    return range.location...(range.location + range.length)
  }
}
