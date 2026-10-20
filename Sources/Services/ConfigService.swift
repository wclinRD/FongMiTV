import Foundation

@MainActor
final class ConfigService: ObservableObject {
    @Published var config: AppConfig?
    @Published var isLoading = false
    @Published var error: String?

    func load(from urlString: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        guard let url = URL(string: urlString) else {
            error = "Invalid URL"
            return
        }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            // Detect HTML landing pages / non-JSON responses
            if let text = String(data: data, encoding: .utf8),
               text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
                self.error = "伺服器回傳 HTML 而非 JSON 配置，請確認 URL 正確。"
                return
            }
            let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
            self.config = decoded
        } catch {
            self.error = "無法解析配置：\(error.localizedDescription)"
        }
    }

    func load(from data: Data) throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: data)
    }

    func save(_ config: AppConfig, to url: URL) throws {
        let data = try JSONEncoder().encode(config)
        try data.write(to: url, options: .atomic)
    }
}
