import SwiftUI

@main
struct FongMiTVApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var server = LocalHTTPServer()
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(server)
                .environmentObject(settings)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear { server.start() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        Settings {
            Form {
                Toggle("簡體轉繁體顯示", isOn: $settings.traditionalizeChinese)
                    .toggleStyle(.switch)
                Text("開啟後，介面中的簡體中文內容會自動轉為繁體中文顯示。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(width: 320)
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var config: AppConfig?
    @Published var sites: [Site] = []
    @Published var selectedSite: Site?
    @Published var isLoading = false
    @Published var errorMessage: String?

    let configService = ConfigService()
    let siteService = SiteService()

    func loadConfig(from url: String) async {
        isLoading = true
        await configService.load(from: url)
        self.config = configService.config
        self.sites = config?.sites ?? []
        let mac = self.sites.first(where: { $0.type == 0 || $0.type == 1 })
        self.selectedSite = mac ?? self.sites.first
        self.errorMessage = configService.error
        isLoading = false
    }
}
