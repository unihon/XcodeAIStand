//
//  SuggestionService.swift
//  XcodeAIStand
//

import Combine
import Foundation

class SuggestionService: ObservableObject {
  static let shared = SuggestionService()

  @Published var currentSuggestion: String? = nil
  @Published var isFetching: Bool = false

  private var cancellables = Set<AnyCancellable>()
  private let debounceSubject = PassthroughSubject<(String, String), Never>()

  private init() {
    Logger.log("[SuggestionService] Initialized")
    setupDebounce()
  }

  private func setupDebounce() {
    debounceSubject
      // 300ms debounce to avoid spamming the API while typing
      .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
      .sink { [weak self] (prefix, suffix) in
        self?.fetchSuggestion(prefix: prefix, suffix: suffix)
      }
      .store(in: &cancellables)
  }

  func onContentChanged(prefix: String, suffix: String) {
    // Clear current suggestion immediately on typing
    currentSuggestion = nil

    Logger.log(
      "[SuggestionService] Content changed. Prefix length: \(prefix.count), Suffix length: \(suffix.count)"
    )

    guard !prefix.isEmpty else { return }
    debounceSubject.send((prefix, suffix))
  }

  private func fetchSuggestion(prefix: String, suffix: String) {
    Logger.log("[SuggestionService] Fetching suggestion from LLM...")
    Task { @MainActor in
      isFetching = true
      defer { isFetching = false }

      do {
        if let prediction = try await LLMService.shared.fetchCompletion(
          prefix: prefix, suffix: suffix),
          !prediction.isEmpty
        {
          self.currentSuggestion = prediction
          Logger.log("[SuggestionService] Suggestion received: \(prediction)")
        } else {
          Logger.log("[SuggestionService] No suggestion or empty response")
        }
      } catch {
        Logger.log("[SuggestionService] Error fetching suggestion: \(error)")
      }
    }
  }

  func acceptSuggestion() {
    guard let suggestion = currentSuggestion else { return }

    // Insert text into Xcode
    XcodeMonitor.shared.insertText(suggestion)
    Logger.log("Accepted suggestion: \(suggestion)")

    // Clear suggestion after accept
    currentSuggestion = nil
  }

  func dismissSuggestion() {
    currentSuggestion = nil
  }
}
