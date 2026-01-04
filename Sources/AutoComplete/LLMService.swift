//
//  LLMService.swift
//  XcodeAIStand
//

import Foundation

class LLMService {
  static let shared = LLMService()

  // Configuration from environment variables
  // AIPP_LLM_URL: Base URL for OpenAI-compatible API (default: http://localhost:11434/v1/chat/completions)
  // AIPP_LLM_KEY: API Key (default: empty)
  // AIPP_LLM_MODEL: Model name (default: llama3)
  private let baseURL: URL
  private let apiKey: String
  private let model: String

  private init() {
    let env = ProcessInfo.processInfo.environment

    let urlString = env["AIPP_LLM_URL"] ?? "http://localhost:11434/v1/chat/completions"
    self.baseURL =
      URL(string: urlString) ?? URL(string: "http://localhost:11434/v1/chat/completions")!
    self.apiKey = env["AIPP_LLM_KEY"] ?? ""
    self.model = env["AIPP_LLM_MODEL"] ?? "llama3"

    Logger.log("[LLMService] Initialized - URL: \(baseURL), Model: \(model)")
  }

  struct CompletionRequest: Codable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let max_tokens: Int

    struct Message: Codable {
      let role: String
      let content: String
    }
  }

  struct CompletionResponse: Codable {
    let choices: [Choice]

    struct Choice: Codable {
      let message: Message
    }

    struct Message: Codable {
      let content: String
    }
  }

  func fetchCompletion(prefix: String, suffix: String) async throws -> String? {
    // Construct the prompt
    // Using FIM (Fill In the Middle) format if supported, or a standard prompt for completion
    // Since we are using a chat model (gemini-3-flash), we'll frame it as a completion task.
    // We'll use a specific system prompt to guide the model.

    let systemPrompt = """
      You are a code completion AI. Your task is to complete the code at the cursor position.
      You will be provided with the code BEFORE the cursor (prefix) and the code AFTER the cursor (suffix).

      Rules:
      1. ONLY return the code that should be inserted at the cursor.
      2. Do NOT return any explanation, markdown formatting, or valid code that is already in the suffix.
      3. If there is no logical completion, return an empty string.
      4. Do not repeat the prefix or suffix in your output.
      """

    let userPrompt = """
      [PREFIX]
      \(prefix)
      [SUFFIX]
      \(suffix)
      [CURSOR]
      """

    let requestBody = CompletionRequest(
      model: self.model,
      messages: [
        .init(role: "system", content: systemPrompt),
        .init(role: "user", content: userPrompt),
      ],
      temperature: 0.1,  // Low temperature for deterministic code
      max_tokens: 50  // Short completion for latency
    )

    var request = URLRequest(url: baseURL)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(requestBody)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
      if let errorText = String(data: data, encoding: .utf8) {
        Logger.log("LLM Error: \(errorText)")
      }
      return nil
    }

    let result = try JSONDecoder().decode(CompletionResponse.self, from: data)
    let content = result.choices.first?.message.content.trimmingCharacters(
      in: .whitespacesAndNewlines)

    // Basic cleanup if the model creates markdown blocks
    let cleanContent = content?
      .replacingOccurrences(of: "```swift", with: "")
      .replacingOccurrences(of: "```", with: "")

    return cleanContent
  }
}
