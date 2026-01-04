//
//  HTTPServer.swift
//  XcodeAIStand
//

import Foundation
import Network

class HTTPServer {
  static let shared = HTTPServer()

  private var listener: NWListener?
  private var currentPort: UInt16 = 8765

  private init() {}

  func start(port: UInt16 = 8765, host: String? = nil) {
    currentPort = port

    do {
      let params = NWParameters.tcp
      params.allowLocalEndpointReuse = true

      // If host is provided, restrict to that local endpoint
      // If host is provided, restrict to that local endpoint
      if let host = host {
        let localEndpoint = NWEndpoint.hostPort(
          host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        params.requiredLocalEndpoint = localEndpoint
        listener = try NWListener(using: params)
      } else {
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
      }

      listener?.stateUpdateHandler = { state in
        switch state {
        case .ready:
          if let host = host {
            Logger.log("✅ HTTP server listening on \(host):\(self.currentPort)")
          } else {
            Logger.log("✅ HTTP server listening on port \(self.currentPort)")
          }
        case .failed(let error):
          Logger.log("❌ Server failed: \(error)")
        default:
          break
        }
      }

      listener?.newConnectionHandler = { [weak self] connection in
        self?.handleConnection(connection)
      }

      listener?.start(queue: .main)
    } catch {
      Logger.log("❌ Failed to start server: \(error)")
    }
  }

  private func handleConnection(_ connection: NWConnection) {
    connection.start(queue: .main)

    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
      guard let data = data, let requestString = String(data: data, encoding: .utf8) else {
        connection.cancel()
        return
      }

      // Parse HTTP method line
      let lines = requestString.components(separatedBy: "\r\n")
      guard let requestLine = lines.first else {
        connection.cancel()
        return
      }

      let isPost = requestLine.hasPrefix("POST")

      var responseData: Data?
      var statusCode = "200 OK"

      if isPost {
        // Handle MCP JSON-RPC Request
        // Extract body (find double newline)
        if let range = requestString.range(of: "\r\n\r\n") {
          let bodyStart = range.upperBound
          let bodyString = String(requestString[bodyStart...])
          if let bodyData = bodyString.data(using: .utf8) {
            responseData = MCPServer.shared.process(data: bodyData)
          }
        }
      } else {
        // Only POST is supported now
        statusCode = "405 Method Not Allowed"
        responseData = "{\"error\": \"Method not allowed. Use POST for MCP JSON-RPC.\"}".data(
          using: .utf8)
      }

      // Build HTTP response
      var response = "HTTP/1.1 \(statusCode)\r\n"
      response += "Content-Type: application/json\r\n"
      response += "Access-Control-Allow-Origin: *\r\n"

      let finalData = responseData ?? "{}".data(using: .utf8)!
      response += "Content-Length: \(finalData.count)\r\n"
      response += "\r\n"

      connection.send(
        content: response.data(using: .utf8),
        completion: .contentProcessed { _ in
          connection.send(
            content: finalData,
            completion: .contentProcessed { _ in
              connection.cancel()
            })
        })
    }
  }
}
