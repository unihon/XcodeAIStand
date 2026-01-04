//
//  CommandLineParser.swift
//  XcodeAIStand
//

import AppKit
import Foundation

/// Parsed command line arguments
struct Args {
  var mode: RunMode = .mcpStdio  // Default: MCP stdio mode
  var listenAddress: (host: String?, port: UInt16)?  // If set, enables HTTP server
  var includeSnippets: Bool = false  // -snippet flag: include code snippets in output
}

/// Parse command line arguments
func parseArguments() -> Args {
  let args = CommandLine.arguments
  var result = Args()

  // Skip executable name
  var i = 1
  while i < args.count {
    let arg = args[i]
    switch arg {
    case "-http":
      result.mode = .mcpHttp
    case "-snippet":
      result.includeSnippets = true
    case "-txt":
      result.mode = .directOutput
    case "-bind":
      // Bind address: [host]:port
      if i + 1 < args.count {
        let bindStr = args[i + 1]
        let parts = bindStr.components(separatedBy: ":")

        var host: String?
        var port: UInt16?

        if parts.count == 2 {
          host = parts[0].isEmpty ? nil : parts[0]
          port = UInt16(parts[1])
        } else if parts.count == 1 {
          port = UInt16(parts[0])
        }

        if let p = port {
          result.listenAddress = (host, p)
        }
        i += 1
      }
    default:
      break
    }
    i += 1
  }

  // If HTTP mode but no bind address, default to port 9000
  if result.mode == .mcpHttp && result.listenAddress == nil {
    result.listenAddress = (nil, 9000)
  }

  return result
}

/// Check accessibility permission
func checkAccessibility() -> Bool {
  let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
  return AXIsProcessTrustedWithOptions(options as CFDictionary)
}
