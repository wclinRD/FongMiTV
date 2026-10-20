import SwiftUI

enum AppSelection: Hashable {
    case dlna
    static func == (lhs: AppSelection, rhs: AppSelection) -> Bool {
        switch (lhs, rhs) {
        case (.site(let a), .site(let b)): return a == b
        case (.live(let a), .live(let b)): return a == b
        case (.dlna, .dlna): return true
        default: return false
        }
    }
    func hash(into hasher: inout Hasher) {
        switch self {
        case .site(let s): hasher.combine(0); hasher.combine(s)
        case .live(let l): hasher.combine(1); hasher.combine(l)
        case .dlna: hasher.combine(2)
        }
    }
    case site(Site)
    case live(LiveConfig)
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var configURL: String = "https://raw.githubusercontent.com/qist/tvbox/refs/heads/master/dianshi.json"
    @State private var showConfigSheet = false
    @State private var selection: AppSelection?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            DetailView(selection: selection)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showConfigSheet = true
                } label: {
                    Label("載入配置", systemImage: "doc.badge.plus")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    appState.config = nil
                    appState.sites = []
                    appState.selectedSite = nil
                    appState.errorMessage = nil
                } label: {
                    Label("清除配置", systemImage: "trash")
                }
                .help("清除已載入的配置")
            }
        }
        .sheet(isPresented: $showConfigSheet) {
            ConfigLoadSheet(configURL: $configURL) { url in
                Task { await appState.loadConfig(from: url) }
            }
        }
        .task {
            if appState.config == nil {
                await appState.loadConfig(from: configURL)
            }
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selection: AppSelection?

    var body: some View {
        List(selection: $selection) {
            Section("站點") {
                ForEach(appState.config?.sites ?? []) { site in
                    NavigationLink(value: AppSelection.site(site)) {
                        Label(site.name.traditionalized(), systemImage: "globe")
                    }
                }
            }
            if let lives = appState.config?.lives, !lives.isEmpty {
                Section("直播") {
                    ForEach(lives) { live in
                        NavigationLink(value: AppSelection.live(live)) {
                            Label((live.name ?? "直播").traditionalized(), systemImage: "tv")
                        }
                    }
                }
            }
            Section("工具") {
                NavigationLink(value: AppSelection.dlna) {
                    Label("DLNA 投放", systemImage: "dot.radiowaves.left.and.right")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("FongMiTV")
    }
}

struct DetailView: View {
    @EnvironmentObject var appState: AppState
    let selection: AppSelection?

    var body: some View {
        switch selection {
        case .site(let site):
            SiteDetailView(site: site)
        case .live(let live):
            LiveView(liveConfig: live)
        case .dlna:
            DLNAView()
        case nil:
            if let config = appState.config {
                ConfigOverview(config: config)
            } else {
                ContentUnavailableView("尚未載入配置", systemImage: "doc", description: Text((appState.errorMessage ?? "點擊工具列「載入配置」輸入配置 URL").traditionalized()))
            }
        }
    }
}

struct ConfigOverview: View {
    let config: AppConfig
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text((config.name ?? "Config").traditionalized()).font(.title)
                if let notice = config.notice { Text(notice.traditionalized()).foregroundStyle(.secondary) }
                Text("站點數：\(config.sites.count)").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                    ForEach(config.sites) { site in
                        VStack(alignment: .leading) {
                            Text(site.name.traditionalized()).font(.headline)
                            Text(site.key).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding()
        }
    }
}

struct SiteDetailView: View {
    let site: Site
    @EnvironmentObject var appState: AppState
    @State private var jsSource: String?
    @State private var homeResult = HomeResult()
    @State private var selectedClass: VodClass?
    @State private var vods: [Vod] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var searchText = ""
    @State private var selectedVod: Vod?
    @State private var currentPage: Int = 1
    @State private var totalCount: Int = 0
    @State private var isLoadingMore: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Category chips
            if !homeResult.classes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(homeResult.classes) { c in
                            Button(c.name.traditionalized()) {
                                selectedClass = c
                                Task { await loadCategory(c.id) }
                            }
                            .buttonStyle(.bordered)
                            .tint(selectedClass?.id == c.id ? .accentColor : .secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }
            // Search bar
            HStack {
                TextField("搜尋", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await doSearch() } }
                Button("搜尋") { Task { await doSearch() } }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            if isLoading { ProgressView().padding() }
            else if let error { Text(error).foregroundStyle(.red).padding() }
            else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 12) {
                        ForEach(vods) { vod in
                            VodCard(vod: vod)
                                .onTapGesture { selectedVod = vod }
                        }
                    }
                    .padding()
                }
                if (totalCount == 0 || vods.count < totalCount) && !vods.isEmpty {
                    HStack {
                        Spacer()
                        if isLoadingMore { ProgressView().scaleEffect(0.7) }
                        Spacer()
                    }
                    .padding(.bottom)
                    .onAppear {
                        Task { await loadMore() }
                    }
                }
            }
        }
        .navigationTitle(site.name.traditionalized())
        .sheet(item: $selectedVod) { vod in
            VodDetailSheet(site: site, jsSource: jsSource, vod: vod)
        }
        .task { await loadHome() }
    }

    private func loadHome() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        jsSource = await SpiderSourceLoader.load(ext: site.ext)
        do {
            let hr = try await appState.siteService.home(site: site, jsSource: jsSource)
            homeResult = hr
            vods = hr.list
            totalCount = hr.list.count
            if let first = hr.classes.first {
                selectedClass = first
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadCategory(_ type: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            currentPage = 1
            let (list, total) = try await appState.siteService.category(site: site, jsSource: jsSource, type: type, page: 1)
            vods = list
            totalCount = total
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func doSearch() async {
        guard !searchText.isEmpty else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            currentPage = 1
            vods = try await appState.siteService.search(site: site, jsSource: jsSource, keyword: searchText)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            if let sc = selectedClass {
                let (list, total) = try await appState.siteService.category(site: site, jsSource: jsSource, type: sc.id, page: currentPage + 1)
                if list.isEmpty {
                    totalCount = vods.count
                } else {
                    vods.append(contentsOf: list)
                    currentPage += 1
                    totalCount = (total > 0) ? total : vods.count
                }
            } else {
                let (list, total) = try await appState.siteService.category(site: site, jsSource: jsSource, type: "0", page: currentPage + 1)
                if list.isEmpty {
                    totalCount = vods.count
                } else {
                    vods.append(contentsOf: list)
                    currentPage += 1
                    totalCount = (total > 0) ? total : vods.count
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct VodDetailSheet: View {
    let site: Site
    let jsSource: String?
    let vod: Vod
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @State private var detail: Vod?
    @State private var isLoading = false
    @State private var episodes: [Episode] = []
    @State private var playUrl: String?
    @State private var playerURL: URL?
    @State private var playHeaders: [String: String] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let pic = vod.vodPic, let url = URL(string: pic) {
                        AsyncImage(url: url) { img in img.resizable().scaledToFit() } placeholder: { ProgressView() }
                            .frame(maxHeight: 260)
                    }
                    Text((vod.vodName ?? "Unknown").traditionalized()).font(.title2).bold()
                    if let remarks = vod.vodRemarks { Text(remarks.traditionalized()).foregroundStyle(.secondary) }
                    if let content = vod.vodContent { Text(content.traditionalized()).font(.body) }
                    if isLoading { ProgressView() }
                    if !episodes.isEmpty {
                        Text("集數").font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                            ForEach(episodes) { ep in
                                Button(ep.name) {
                                    Task { await play(ep) }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    if let playerURL {
                        PlayerView(url: playerURL, title: vod.vodName, headers: playHeaders)
                            .frame(height: 360)
                    }
                }
                .padding()
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("關閉") { dismiss() } } }
        }
        .task { await loadDetail() }
    }

    private func loadDetail() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let ids = [vod.vodId].compactMap { $0 }
            let vs = try await appState.siteService.detail(site: site, jsSource: jsSource, ids: ids)
            if let d = vs.first {
                detail = d
                episodes = parseEpisodes(d)
            } else {
                episodes = parseEpisodes(vod)
            }
        } catch {
            episodes = parseEpisodes(vod)
        }
    }

    private func parseEpisodes(_ v: Vod) -> [Episode] {
        // vodPlayUrl format: "集名$URL#集名$URL" or "URL#URL"
        guard let playUrl = v.vodPlayUrl, !playUrl.isEmpty else { return [] }
        var result: [Episode] = []
        for group in playUrl.split(separator: "$$$") {
            for item in String(group).split(separator: "#") {
                let parts = item.split(separator: "$", maxSplits: 1)
                if parts.count == 2 {
                    result.append(Episode(name: String(parts[0]), url: String(parts[1])))
                } else if parts.count == 1, !parts[0].isEmpty {
                    result.append(Episode(name: "第\(result.count+1)集", url: String(parts[0])))
                }
            }
        }
        return result
    }

    private func play(_ ep: Episode) async {
        do {
            let flag = vod.vodPlayFrom ?? ""
            let (url, headers, _) = try await appState.siteService.play(site: site, jsSource: jsSource, flag: flag, url: ep.url)
            playHeaders = headers
            if let u = URL(string: url) { playerURL = u }
        } catch {
            playHeaders = [:]
            if let u = URL(string: ep.url) { playerURL = u }
        }
    }
}

struct VodCard: View {
    let vod: Vod
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading) {
                AsyncImage(url: URL(string: vod.vodPic ?? "")) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(height: 180)
                .clipped()
                .cornerRadius(8)
                Text((vod.vodName ?? "Unknown").traditionalized()).font(.caption).lineLimit(2)
                if let r = vod.vodRemarks { Text(r.traditionalized()).font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .buttonStyle(.plain)
    }
}

struct ConfigLoadSheet: View {
    @Binding var configURL: String
    var onLoad: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var history: [String] = ConfigURLHistory.list()

    var body: some View {
        VStack(spacing: 16) {
            Text("載入配置".traditionalized()).font(.headline)
            TextField("配置 URL", text: $configURL)
                .textFieldStyle(.roundedBorder)
            if !history.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("過去載入的 URL").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("清除歷史") {
                            ConfigURLHistory.clear()
                            history = []
                        }
                        .font(.caption)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(history, id: \.self) { url in
                                Button {
                                    configURL = url
                                } label: {
                                    Text(url).font(.caption).lineLimit(1).truncationMode(.middle)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
            }
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("載入") {
                    ConfigURLHistory.add(configURL)
                    onLoad(configURL)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(configURL.isEmpty)
            }
        }
        .padding()
        .frame(width: 420)
    }
}
