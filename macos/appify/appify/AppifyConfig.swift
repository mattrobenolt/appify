import Foundation

struct AppifyConfig: Codable {
  var command: String
  var title: String?
  var cwd: String?
  var env: [String: String]?

  static func load() -> AppifyConfig {
    guard let url = Bundle.main.url(forResource: "appify", withExtension: "json") else {
      fatalError("appify.json not found in bundle")
    }

    do {
      let data = try Data(contentsOf: url)
      return try JSONDecoder().decode(AppifyConfig.self, from: data)
    } catch {
      fatalError("appify: failed to read appify.json: \(error)")
    }
  }

  var resolvedCommand: String {
    let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      fatalError("appify: appify.json command is empty")
    }
    return trimmed
  }

  var resolvedTitle: String {
    let trimmed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? resolvedCommand : trimmed
  }

  var envPairs: [(String, String)] {
    return (env ?? [:]).map { ($0.key, $0.value) }
  }
}
