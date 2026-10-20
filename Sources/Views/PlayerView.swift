import SwiftUI
import AVKit
import AVFoundation
import Combine

struct PlayerView: View {
    let url: URL
    let title: String?
    var headers: [String: String] = [:]
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var speed: Double = 1.0
    @State private var cues: [SubtitleCue] = []
    @State private var currentSubtitle: String? = nil
    @State private var errorMessage: String? = nil
    private let speeds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                if let player {
                    PiPPlayerView(player: player)
                } else {
                    Rectangle().fill(.black)
                }
                if let sub = currentSubtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                        .padding(.bottom, 12)
                }
                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(6)
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                        .padding(.bottom, 40)
                }
            }
            .frame(minHeight: 300)
            HStack(spacing: 12) {
                ForEach(speeds, id: \.self) { s in
                    Button(String(format: "%.2gx", s).replacingOccurrences(of: ".00x", with: "x")) {
                        setSpeed(s)
                    }
                    .buttonStyle(.bordered)
                    .tint(speed == s ? .accentColor : .secondary)
                }
                Spacer()
                Button {
                    pickSubtitle()
                } label: { Image(systemName: "captions.bubble") }
                .buttonStyle(.bordered)
                if let player {
                    Button {
                        player.seek(to: .zero)
                    } label: { Image(systemName: "backward.end.fill") }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .onAppear {
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            let item = AVPlayerItem(asset: asset)
            let p = AVPlayer(playerItem: item)
            self.player = p
            PlaybackState.shared.update(url: url.absoluteString, title: title, isPlaying: true, speed: 1.0)
            // observe errors
            Task {
                while self.player != nil {
                    if let item = p.currentItem, item.status == .failed {
                        self.errorMessage = item.error?.localizedDescription ?? "播放失敗"
                        break
                    }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            p.play()
            let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
            timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { t in
                Task { @MainActor in
                    let pos = CMTimeGetSeconds(t)
                    PlaybackState.shared.update(
                        isPlaying: p.rate > 0,
                        duration: p.currentItem.map { CMTimeGetSeconds($0.duration) } ?? 0,
                        position: pos
                    )
                    currentSubtitle = SubtitleService.currentText(cues: cues, time: pos)
                }
            }
        }
        .onDisappear {
            if let obs = timeObserver { player?.removeTimeObserver(obs) }
            timeObserver = nil
            player?.pause()
            player = nil
            PlaybackState.shared.reset()
        }
    }

    private func pickSubtitle() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "srt")!, .init(filenameExtension: "vtt")!]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            cues = SubtitleService.load(url: url)
        }
    }

    private func setSpeed(_ s: Double) {
        speed = s
        player?.rate = Float(s)
        PlaybackState.shared.update(speed: s)
    }
}
