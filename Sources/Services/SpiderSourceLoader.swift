import Foundation

enum SpiderSourceLoader {
    /// Resolve a spider JS source string from a site's `ext` field.
    static func load(ext: String?) async -> String? {
        guard let ext, !ext.isEmpty else { return nil }
        if ext.hasPrefix("http://") || ext.hasPrefix("https://") {
            // Could be a URL to a JS file or a JSON config. Try fetch as text.
            guard let url = URL(string: ext) else { return nil }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let text = String(data: data, encoding: .utf8) {
                    // If it's a JSON with a "spider" or "js" field, extract; otherwise treat as JS.
                    if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let js = obj["js"] as? String { return js }
                        if let spider = obj["spider"] as? String { return spider }
                    }
                    return text
                }
            } catch {
                return nil
            }
            return nil
        }
        // Inline: could be JSON or raw JS
        if let data = ext.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let js = obj["js"] as? String { return js }
            if let spider = obj["spider"] as? String { return spider }
        }
        return ext
    }
}
