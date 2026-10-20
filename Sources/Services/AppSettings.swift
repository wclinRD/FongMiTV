import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    @AppStorage("traditionalizeChinese") var traditionalizeChinese: Bool = true
}

extension String {
    /// 將簡體中文轉為繁體中文（顯示用）
    @MainActor
    func traditionalized(enabled: Bool = AppSettings.shared.traditionalizeChinese) -> String {
        guard enabled else { return self }
        return self.applyingTransform(StringTransform("Simplified-Traditional"), reverse: false) ?? self
    }
}

/// Simple persisted history of loaded config URLs.
enum ConfigURLHistory {
    private static let key = "configURLHistory"
    static func list() -> [String] {
        (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
    }
    static func add(_ url: String) {
        guard !url.isEmpty else { return }
        var arr = list()
        arr.removeAll { $0 == url }
        arr.insert(url, at: 0)
        if arr.count > 10 { arr = Array(arr.prefix(10)) }
        UserDefaults.standard.set(arr, forKey: key)
    }
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
