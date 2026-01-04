//
//  MCPServer.swift
//  XcodeAIStand - MCP (Model Context Protocol) Server
//

import Foundation

class MCPServer {
  static let shared = MCPServer()

  private init() {}

  func startStdioMode() {
    // Disable stdout buffering for immediate output
    setbuf(stdout, nil)

    FileHandle.standardInput.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      if data.isEmpty {
        exit(0)
      }

      guard let string = String(data: data, encoding: .utf8) else { return }

      let lines = string.components(separatedBy: .newlines)
      for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        if let lineData = line.data(using: .utf8) {
          if let responseData = self?.process(data: lineData) {
            // Write response directly to stdout with newline delimiter
            var outputData = responseData
            outputData.append(contentsOf: [0x0A])  // Append newline byte
            FileHandle.standardOutput.write(outputData)
          }
        }
      }
    }
  }

  func process(data: Data) -> Data? {
    do {
      let request = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
      guard let response = handleRequest(request) else {
        // No response needed (e.g., for notifications)
        return nil
      }

      let encoder = JSONEncoder()
      // encoder.outputFormatting = .prettyPrinted // Disable pretty print for MCP (LDJ)
      return try encoder.encode(response)
    } catch {
      // Return error response
      let errorResponse = JSONRPCResponse(
        jsonrpc: "2.0",
        id: nil,
        error: JSONRPCError(code: -32700, message: "Parse error")
      )
      // Try to encode error response
      let encoder = JSONEncoder()
      // encoder.outputFormatting = .prettyPrinted // Disable pretty print for MCP (LDJ)
      return try? encoder.encode(errorResponse)
    }
  }

  private func handleRequest(_ request: JSONRPCRequest) -> JSONRPCResponse? {
    switch request.method {
    case "initialize":
      return handleInitialize(request)
    case "notifications/initialized", "initialized":
      // This is a notification (no response required)
      return nil
    case "tools/list":
      return handleToolsList(request)
    case "tools/call":
      return handleToolsCall(request)
    case "resources/list":
      return handleResourcesList(request)
    case "resources/read":
      return handleResourcesRead(request)
    default:
      // Check if it's a notification (no id means notification, no response needed)
      if request.id == nil {
        return nil
      }
      return JSONRPCResponse(
        jsonrpc: "2.0",
        id: request.id,
        error: JSONRPCError(code: -32601, message: "Method not found")
      )
    }
  }

  private func handleInitialize(_ request: JSONRPCRequest) -> JSONRPCResponse {
    let result: [String: Any] = [
      "protocolVersion": "2024-11-05",
      "capabilities": [
        "tools": [:],
        "resources": [:],
      ],
      "serverInfo": [
        "name": "XcodeAIStand",
        "version": "1.0.0",
      ],
    ]

    return JSONRPCResponse(
      jsonrpc: "2.0",
      id: request.id,
      result: result
    )
  }

  private func handleResourcesList(_ request: JSONRPCRequest) -> JSONRPCResponse {
    let resources: [[String: Any]] = [
      [
        "uri": "XcodeAIStand://project_current_active_file_info",
        "name": "project_current_active_file_info",
        "description":
          "Get current active file info including file path, cursor position, and selected text",
        "mimeType": "text/plain",
      ]
    ]

    let result: [String: Any] = [
      "resources": resources
    ]

    return JSONRPCResponse(
      jsonrpc: "2.0",
      id: request.id,
      result: result
    )
  }

  private func handleResourcesRead(_ request: JSONRPCRequest) -> JSONRPCResponse {
    guard let params = request.params?.value as? [String: Any],
      let uri = params["uri"] as? String
    else {
      return JSONRPCResponse(
        jsonrpc: "2.0",
        id: request.id,
        error: JSONRPCError(code: -32602, message: "Missing 'uri' parameter")
      )
    }

    switch uri {
    case "XcodeAIStand://project_current_active_file_info":
      let output = buildActiveFileInfoOutput()
      let result: [String: Any] = [
        "contents": [
          [
            "uri": uri,
            "mimeType": "text/plain",
            "text": output,
          ]
        ]
      ]
      return JSONRPCResponse(
        jsonrpc: "2.0",
        id: request.id,
        result: result
      )

    default:
      return JSONRPCResponse(
        jsonrpc: "2.0",
        id: request.id,
        error: JSONRPCError(code: -32002, message: "Unknown resource: \(uri)")
      )
    }
  }

  // Helper to build active file info output (used by both tool and resource)
  private func buildActiveFileInfoOutput() -> String {
    let includeSnippets = AppConfig.shared.includeSnippets
    let fileInfo = XcodeMonitor.shared.getFileInfo(includeSnippets: includeSnippets)

    var output = "<PROJECT_CURRENT_ACTIVE_FILE_INFO>\n"
    output += "The user's current state is as follows:\n"

    if let filePath = fileInfo["filePath"] as? String {
      output += "Active Document: \(filePath)\n"
    } else if let error = fileInfo["error"] as? String {
      output += "Error: \(error)\n"
    }

    if let line = fileInfo["cursorLine"] as? Int,
      let column = fileInfo["cursorColumn"] as? Int
    {
      output += "Cursor: Line \(line), Column \(column)\n"
    }

    // Output selection range if present
    if let startLine = fileInfo["selectionStartLine"] as? Int,
      let startColumn = fileInfo["selectionStartColumn"] as? Int,
      let endLine = fileInfo["selectionEndLine"] as? Int,
      let endColumn = fileInfo["selectionEndColumn"] as? Int
    {
      output += "Selection Range: Line \(startLine):\(startColumn) - Line \(endLine):\(endColumn)\n"
    }

    // Only output snippets when -s flag is used
    if includeSnippets {
      if let selectedText = fileInfo["selectedText"] as? String {
        output += "Selected Text:\n\(selectedText)\n"
      }

      if let prev = fileInfo["previousSnippet"] as? String, !prev.isEmpty {
        output += "Previous Snippet:\n```\n\(prev)\n```\n"
      }

      if let next = fileInfo["nextSnippet"] as? String, !next.isEmpty {
        output += "Next Snippet:\n```\n\(next)\n```\n"
      }
    }

    output += "</PROJECT_CURRENT_ACTIVE_FILE_INFO>"
    return output
  }

  private func handleToolsList(_ request: JSONRPCRequest) -> JSONRPCResponse {
    let tools: [[String: Any]] = [
      [
        "name": "get_project_current_active_file_info",
        "description":
          "Get current active file info. Must be called when the question contains keywords like 'here', 'this', 'current', 'selected', 'now', etc.",
        "inputSchema": [
          "type": "object",
          "properties": [:] as [String: Any],
          "required": [] as [String],
        ],
      ],
      [
        "name": "get_file_content",
        "description": "Get the complete content of a specified file",
        "inputSchema": [
          "type": "object",
          "properties": [
            "path": [
              "type": "string",
              "description": "Absolute path to the file",
            ]
          ],
          "required": ["path"],
        ],
      ],
      [
        "name": "list_directory",
        "description":
          "Recursively list files in a directory, ignoring hidden files and common build directories",
        "inputSchema": [
          "type": "object",
          "properties": [
            "path": [
              "type": "string",
              "description": "Root path to start listing from",
            ]
          ],
          "required": ["path"],
        ],
      ],
      [
        "name": "get_project_structure",
        "description": "Get the file structure of the current project",
        "inputSchema": [
          "type": "object",
          "properties": [:] as [String: Any],
          "required": [] as [String],
        ],
      ],
    ]

    let result: [String: Any] = [
      "tools": tools
    ]

    return JSONRPCResponse(
      jsonrpc: "2.0",
      id: request.id,
      result: result
    )
  }

  private func handleToolsCall(_ request: JSONRPCRequest) -> JSONRPCResponse {
    // Extract params safely
    guard let params = request.params?.value as? [String: Any],
      let toolName = params["name"] as? String
    else {
      return JSONRPCResponse(
        jsonrpc: "2.0",
        id: request.id,
        error: JSONRPCError(code: -32602, message: "Invalid params")
      )
    }

    switch toolName {
    case "get_project_current_active_file_info":
      let output = buildActiveFileInfoOutput()

      let result: [String: Any] = [
        "content": [
          [
            "type": "text",
            "text": output,
          ]
        ]
      ]

      return JSONRPCResponse(
        jsonrpc: "2.0",
        id: request.id,
        result: result
      )

    case "get_file_content":
      guard let arguments = params["arguments"] as? [String: Any],
        let path = arguments["path"] as? String
      else {
        return JSONRPCResponse(
          jsonrpc: "2.0",
          id: request.id,
          error: JSONRPCError(code: -32602, message: "Missing 'arguments.path' parameter")
        )
      }

      var content: String
      do {
        content = try String(contentsOfFile: path, encoding: .utf8)
      } catch {
        return JSONRPCResponse(
          jsonrpc: "2.0",
          id: request.id,
          error: JSONRPCError(
            code: -32000, message: "Failed to read file: \(error.localizedDescription)")
        )
      }

      let result: [String: Any] = [
        "content": [
          [
            "type": "text",
            "text": content,
          ]
        ]
      ]

      return JSONRPCResponse(
        jsonrpc: "2.0",
        id: request.id,
        result: result
      )

    case "list_directory":
      guard let arguments = params["arguments"] as? [String: Any],
        let path = arguments["path"] as? String
      else {
        return JSONRPCResponse(
          jsonrpc: "2.0",
          id: request.id,
          error: JSONRPCError(code: -32602, message: "Missing 'arguments.path' parameter")
        )
      }

      let files = listFiles(at: path)
      let output = files.joined(separator: "\n")

      let result: [String: Any] = [
        "content": [
          [
            "type": "text",
            "text": output,
          ]
        ]
      ]

      return JSONRPCResponse(
        jsonrpc: "2.0",
        id: request.id,
        result: result
      )

    case "get_project_structure":
      guard let rootPath = XcodeMonitor.shared.getProjectRoot() else {
        return JSONRPCResponse(
          jsonrpc: "2.0",
          id: request.id,
          error: JSONRPCError(code: -32000, message: "Could not detect Xcode project root")
        )
      }

      let files = listFiles(at: rootPath)
      let output = "Project Root: \(rootPath)\n\n" + files.joined(separator: "\n")

      let result: [String: Any] = [
        "content": [
          [
            "type": "text",
            "text": output,
          ]
        ]
      ]

      return JSONRPCResponse(
        jsonrpc: "2.0",
        id: request.id,
        result: result
      )

    default:
      return JSONRPCResponse(
        jsonrpc: "2.0",
        id: request.id,
        error: JSONRPCError(code: -32602, message: "Unknown tool: \(toolName)")
      )
    }
  }

  // Helper to list files recursively
  private func listFiles(at path: String) -> [String] {
    let fileManager = FileManager.default
    var files: [String] = []

    let url = URL(fileURLWithPath: path)
    if let enumerator = fileManager.enumerator(
      at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
    {
      for case let fileURL as URL in enumerator {
        let pathComponents = fileURL.pathComponents
        if pathComponents.contains(".git") || pathComponents.contains(".build")
          || pathComponents.contains(".swiftpm")
        {
          continue
        }

        if let isRegularFile = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
          .isRegularFile, isRegularFile
        {
          files.append(fileURL.path)
        }
      }
    }
    return files.sorted()
  }

  // Helper for internal use if needed, but primary output is via data return
  private func sendResponse(_ response: JSONRPCResponse) {
    // This method is now legacy/helper for internal logic if needed
  }

  // Helper for legacy sendError
  private func sendError(id: AnyCodable?, code: Int, message: String) {
    // No-op or log, since we now return data
  }
}

// MARK: - JSON-RPC Models

struct JSONRPCRequest: Codable {
  let jsonrpc: String
  let id: AnyCodable?
  let method: String
  let params: AnyCodable?
}

struct JSONRPCResponse: Codable {
  let jsonrpc: String
  let id: AnyCodable?
  let result: AnyCodable?
  let error: JSONRPCError?

  init(jsonrpc: String, id: AnyCodable?, result: Any) {
    self.jsonrpc = jsonrpc
    self.id = id
    self.result = AnyCodable(result)
    self.error = nil
  }

  init(jsonrpc: String, id: AnyCodable?, error: JSONRPCError) {
    self.jsonrpc = jsonrpc
    self.id = id
    self.result = nil
    self.error = error
  }
}

struct JSONRPCError: Codable {
  let code: Int
  let message: String
}

// MARK: - AnyCodable Helper

struct AnyCodable: Codable {
  let value: Any

  init(_ value: Any) {
    self.value = value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self.value = NSNull()
    } else if let bool = try? container.decode(Bool.self) {
      self.value = bool
    } else if let int = try? container.decode(Int.self) {
      self.value = int
    } else if let double = try? container.decode(Double.self) {
      self.value = double
    } else if let string = try? container.decode(String.self) {
      self.value = string
    } else if let array = try? container.decode([AnyCodable].self) {
      self.value = array.map { $0.value }
    } else if let dictionary = try? container.decode([String: AnyCodable].self) {
      self.value = dictionary.mapValues { $0.value }
    } else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()

    switch value {
    case is NSNull:
      try container.encodeNil()
    case let bool as Bool:
      try container.encode(bool)
    case let int as Int:
      try container.encode(int)
    case let double as Double:
      try container.encode(double)
    case let string as String:
      try container.encode(string)
    case let array as [Any]:
      try container.encode(array.map { AnyCodable($0) })
    case let dictionary as [String: Any]:
      try container.encode(dictionary.mapValues { AnyCodable($0) })
    default:
      throw EncodingError.invalidValue(
        value,
        EncodingError.Context(
          codingPath: container.codingPath, debugDescription: "Unsupported type")
      )
    }
  }
}
