import SwiftUI
import AVKit
import Combine

struct PlayerView: View {
    let url: URL
    let title: String?
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                let p = AVPlayer(url: url)
                self.player = p
                PlaybackState.shared.update(url: url.absoluteString, title: title, isPlaying: true)
                p.play()
                // time observer
                let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
                timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { t in
                    Task { @MainActor in
                        PlaybackState.shared.update(
                            isPlaying: p.rate > 0,
                            duration: p.currentItem.map { CMTimeGetSeconds($0.duration) } ?? 0,
                            position: CMTimeGetSeconds(t)
                        )
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
}
