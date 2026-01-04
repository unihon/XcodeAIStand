//
//  Logger.swift
//  XcodeAIStand
//

import Foundation

enum Logger {
  static var enabled = true

  static func log(_ message: String) {
    guard enabled else { return }
    let logMessage = message + "\n"
    if let data = logMessage.data(using: .utf8) {
      FileHandle.standardError.write(data)
    }
  }
}
