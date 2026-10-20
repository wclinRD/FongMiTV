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
