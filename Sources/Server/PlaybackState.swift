import Foundation
import Combine

@MainActor
final class PlaybackState: ObservableObject {
    static let shared = PlaybackState()
    @Published var url: String = ""
    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var artwork: String = ""
    @Published var isPlaying: Bool = false
    @Published var speed: Double = 1.0
    @Published var duration: Double = 0
    @Published var position: Double = 0
    @Published var state: Int = 1 // 1 stopped, 2 ready, 3 playing, 6 buffering

    func update(url: String? = nil, title: String? = nil, isPlaying: Bool? = nil,
               speed: Double? = nil, duration: Double? = nil, position: Double? = nil) {
        if let url { self.url = url }
        if let title { self.title = title }
        if let isPlaying {
            self.isPlaying = isPlaying
            self.state = isPlaying ? 3 : 2
        }
        if let speed { self.speed = speed }
        if let duration { self.duration = duration }
        if let position { self.position = position }
    }

    func reset() {
        url = ""; title = ""; artist = ""; artwork = ""
        isPlaying = false; speed = 1.0; duration = 0; position = 0; state = 1
    }

    var json: String {
        let obj: [String: Any] = [
            "state": state,
            "speed": speed,
            "duration": duration,
            "position": position,
            "url": url,
            "title": title,
            "artist": artist,
            "artwork": artwork
        ]
        if let data = try? JSONSerialization.data(withJSONObject: obj),
           let str = String(data: data, encoding: .utf8) { return str }
        return "{}"
    }
}
