//
//  main.swift
//  XcodeAIStand - Xcode file monitor service
//

import AppKit
import Foundation

// MARK: - Helper Functions

// Cache file path for storing last active state
let cacheFilePath = NSHomeDirectory() + "/.aipp_last_state"

// Create a state key from file info for comparison
func createStateKey(from info: [String: Any]) -> String {
  let filePath = info["filePath"] as? String ?? ""
  let line = info["cursorLine"] as? Int ?? 0
  let column = info["cursorColumn"] as? Int ?? 0
  return "\(filePath):\(line):\(column)"
}

// Read last cached state
func readLastState() -> String? {
  return try? String(contentsOfFile: cacheFilePath, encoding: .utf8)
}

// Save current state to cache
func saveState(_ state: String) {
  try? state.write(toFile: cacheFilePath, atomically: true, encoding: .utf8)
}

// Print file info to console (Direct output mode with -txt)
func printFileInfo() {
  let monitor = XcodeMonitor.shared
  let info = monitor.getFileInfo(includeSnippets: true)

  // Get project root for relative path conversion
  let projectRoot = monitor.getProjectRoot()

  // Build PROJECT_CURRENT_ACTIVE_FILE_INFO format
  var output = "<PROJECT_CURRENT_ACTIVE_FILE_INFO>\n"

  output += "The user's current state is as follows:\n"

  // Active document (use relative path if project root is available)
  if let filePath = info["filePath"] as? String {
    var displayPath = filePath
    if let root = projectRoot, filePath.hasPrefix(root) {
      // Convert to relative path
      let relativePath = String(filePath.dropFirst(root.count))
      displayPath = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
    }
    output += "Active Document: \(displayPath)\n"
    if let root = projectRoot {
      output += "Project Root: \(root)\n"
    }
  } else if let error = info["error"] as? String {
    output += "Error: \(error)\n"
  }

  // Cursor position
  if let line = info["cursorLine"] as? Int,
    let column = info["cursorColumn"] as? Int
  {
    output += "Cursor: Line \(line), Column \(column)\n"
  }

  // Selected text
  if let selectedText = info["selectedText"] as? String {
    output += "Selected Text:\n```\n\(selectedText)\n```\n"
  }

  // Previous snippet
  if let prev = info["previousSnippet"] as? String, !prev.isEmpty {
    output += "Previous Snippet:\n```\n\(prev)\n```\n"
  }

  // Next snippet
  if let next = info["nextSnippet"] as? String, !next.isEmpty {
    output += "Next Snippet:\n```\n\(next)\n```\n"
  }

  output += "</PROJECT_CURRENT_ACTIVE_FILE_INFO>"
  print(output)
}

// MARK: - Main

let args = parseArguments()

// Apply global configuration
AppConfig.shared.includeSnippets = args.includeSnippets

if !checkAccessibility() {
  Logger.log("⚠️  Accessibility permission required!")
  Logger.log("   Go to: System Settings → Privacy & Security → Accessibility")
  Logger.log("   Add: .build/release/XcodeAIStand")
  exit(1)
}

// Disable logs immediately if in stdio mode to prevent pollution
if args.mode == .mcpStdio {
  Logger.enabled = false
}

// Direct output mode (-txt): just print and exit
if args.mode == .directOutput {
  printFileInfo()
  exit(0)
}

// For long-running modes, replace standard print with Logger (stderr) to keep stdout clean for MCP
if args.mode != .mcpStdio {
  Logger.log("🚀 XcodeAIStand starting...")
}

// Check if experimental code completion is enabled via AIPP_COMPLETION=1
let enableCompletion = ProcessInfo.processInfo.environment["AIPP_COMPLETION"] == "1"

if enableCompletion {
  if args.mode != .mcpStdio {
    Logger.log("✨ [EXPERIMENTAL] Code Completion enabled via AIPP_COMPLETION=1")
  }
  _ = SuggestionWidgetController.shared
  _ = SuggestionService.shared
  InputInterceptor.shared.start()
}

// Start monitoring Xcode
let monitor = XcodeMonitor.shared
monitor.start(enableCompletion: enableCompletion)

// MCP Mode logic:
// -http with -b -> HTTP Protocol
// Default (no args) -> Stdio Protocol
switch args.mode {
case .mcpHttp:
  let (host, port) = args.listenAddress ?? (nil, 9000)
  Logger.log("🌍 Starting HTTP Server (MCP Protocol) on port \(port)...")
  HTTPServer.shared.start(port: port, host: host)
case .mcpStdio:
  MCPServer.shared.startStdioMode()
case .directOutput:
  break  // Already handled above
}

if args.mode != .mcpStdio {
  Logger.log("✅ Services running. Press Ctrl+C to stop.")
}

// Keep running
RunLoop.main.run()
