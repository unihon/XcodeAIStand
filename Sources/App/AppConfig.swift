//
//  AppConfig.swift
//  XcodeAIStand
//

import Foundation

/// Global configuration accessible by other modules
class AppConfig {
  static let shared = AppConfig()
  var includeSnippets: Bool = false
  private init() {}
}

/// Run mode for the application
enum RunMode {
  case mcpStdio  // Default (no args): MCP stdio mode
  case mcpHttp  // -http: MCP HTTP mode
  case directOutput  // -txt: Direct output mode (just PROJECT_CURRENT_ACTIVE_FILE_INFO content)
}
