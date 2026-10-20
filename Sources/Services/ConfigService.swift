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
        let ext = url.pathExtension.lowercased()
        // Support loading a MacCMS provider URL directly (e.g. .../api.php/provide/vod)
        if ext != "json" && ext != "py" && ext != "js" {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                // Try MacCMS response
                if let resp = try? JSONDecoder().decode(MacCMSResponse.self, from: data), (resp.list != nil || resp.classList != nil) {
                    var cfg = AppConfig()
                    cfg.name = url.host ?? "MacCMS"
                    var site = Site(key: "direct_mac", name: url.host ?? "MacCMS")
                    site.type = 1
                    site.api = urlString
                    site.searchable = 1
                    site.quickSearch = 1
                    site.filterable = 1
                    site.changeable = 1
                    cfg.sites = [site]
                    self.config = cfg
                    return
                }
                // Generic JSON with list key
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   obj["list"] != nil {
                    var cfg = AppConfig()
                    cfg.name = url.host ?? "Source"
                    var site = Site(key: "direct_src", name: url.host ?? "Source")
                    site.type = 1
                    site.api = urlString
                    site.searchable = 1
                    cfg.sites = [site]
                    self.config = cfg
                    return
                }
            } catch {
                // fall through to normal handling
            }
        }
        // Support loading a Python/JS spider directly as a single-site config
        if ext == "py" || ext == "js" {
            var cfg = AppConfig()
            cfg.name = url.lastPathComponent
            var site = Site(key: "direct_\(ext)", name: url.lastPathComponent)
            site.type = 3
            site.api = ""
            site.ext = urlString
            site.searchable = 1
            site.quickSearch = 1
            site.filterable = 1
            site.changeable = 1
            cfg.sites = [site]
            self.config = cfg
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
