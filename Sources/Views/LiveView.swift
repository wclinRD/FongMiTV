import SwiftUI
import AVKit

struct LiveView: View {
    let liveConfig: LiveConfig
    @StateObject private var service = LiveService()
    @State private var selectedChannel: LiveChannel?
    @State private var playerURL: URL?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text((liveConfig.name ?? "直播").traditionalized()).font(.title2).bold()
                Spacer()
                if service.isLoading { ProgressView().scaleEffect(0.7) }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            HStack {
                TextField("搜尋頻道", text: $searchText).textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            if let err = service.error {
                Text(err).foregroundStyle(.red).padding()
            }

            HSplitView {
                // Channel list
                List(selection: $selectedChannel) {
                    let grouped = Dictionary(grouping: filteredChannels) { $0.group ?? "未分組" }
                    ForEach(grouped.keys.sorted(), id: \.self) { group in
                        Section(group.traditionalized()) {
                            ForEach(grouped[group] ?? []) { ch in
                                HStack {
                                    if let logo = ch.logo, let url = URL(string: logo) {
                                        AsyncImage(url: url) { img in img.resizable() } placeholder: { Color.gray }
                                            .frame(width: 28, height: 28).cornerRadius(4)
                                    }
                                    Text(ch.name?.traditionalized() ?? "頻道")
                                }
                                .tag(ch)
                                .onTapGesture {
                                    selectedChannel = ch
                                    if let u = URL(string: ch.url ?? "") { playerURL = u }
                                }
                            }
                        }
                    }
                }
                .frame(minWidth: 220)
                .listStyle(.sidebar)

                // Player + EPG
                VStack {
                    if let playerURL {
                        PlayerView(url: playerURL, title: selectedChannel?.name)
                            .frame(minHeight: 300)
                    } else {
                        ContentUnavailableView("選擇頻道", systemImage: "tv", description: Text("從左側選擇直播頻道"))
                    }
                    if let ch = selectedChannel {
                        EpgListView(channel: ch, epg: service.epg)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await service.load(from: liveConfig) }
    }

    private var filteredChannels: [LiveChannel] {
        if searchText.isEmpty { return service.channels }
        return service.channels.filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
    }
}

struct EpgListView: View {
    let channel: LiveChannel
    let epg: [String: [EpgProgram]]

    private var programs: [EpgProgram] {
        let key = channel.epgId ?? channel.name ?? ""
        return epg[key] ?? epg[channel.name ?? ""] ?? []
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("節目表").font(.headline).padding(.horizontal)
            if programs.isEmpty {
                Text("無 EPG 資料").foregroundStyle(.secondary).padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(programs) { p in
                            HStack {
                                if let s = p.start {
                                    Text(timeString(s)).font(.caption).monospacedDigit()
                                }
                                Text(p.title?.traditionalized() ?? "").font(.caption)
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
        }
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}
