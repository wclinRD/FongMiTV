import SwiftUI

struct DLNAView: View {
    @StateObject private var service = DLNAService()
    @State private var playURL: String = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("DLNA 裝置").font(.title2).bold()
                Spacer()
                Button {
                    Task { await service.search() }
                } label: {
                    if service.isSearching { ProgressView().scaleEffect(0.7) } else { Label("搜尋", systemImage: "magnifyingglass") }
                }
                .disabled(service.isSearching)
            }
            .padding(.horizontal)

            HStack {
                TextField("播放 URL", text: $playURL).textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)

            List(service.devices) { dev in
                HStack {
                    VStack(alignment: .leading) {
                        Text(dev.name)
                        Text(dev.location).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("投放") {
                        Task { await service.play(on: dev, url: playURL) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(playURL.isEmpty)
                }
            }
            .listStyle(.plain)
        }
        .padding(.vertical)
    }
}
