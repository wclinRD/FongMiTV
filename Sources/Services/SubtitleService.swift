import Foundation

struct SubtitleCue {
    let start: Double
    let end: Double
    let text: String
}

enum SubtitleService {
    static func load(url: URL) -> [SubtitleCue] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        if url.pathExtension.lowercased() == "vtt" {
            return parseVTT(text)
        }
        return parseSRT(text)
    }

    static func parseSRT(_ text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let blocks = text.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard lines.count >= 2 else { continue }
            // find timing line
            var timingIdx = -1
            for (i, l) in lines.enumerated() {
                if l.contains("-->") { timingIdx = i; break }
            }
            guard timingIdx >= 0 else { continue }
            let timing = lines[timingIdx]
            let parts = timing.components(separatedBy: "-->")
            guard parts.count == 2 else { continue }
            let start = parseTime(parts[0])
            let end = parseTime(parts[1])
            let cueText = lines[(timingIdx+1)...].joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            cues.append(SubtitleCue(start: start, end: end, text: cueText))
        }
        return cues
    }

    static func parseVTT(_ text: String) -> [SubtitleCue] {
        // strip header
        var body = text
        if let range = body.range(of: "\n\n") { body = String(body[range.upperBound...]) }
        return parseSRT(body)
    }

    static func parseTime(_ s: String) -> Double {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        // format hh:mm:ss,ms or mm:ss.mmm
        let parts = trimmed.components(separatedBy: ",")
        let timePart = parts[0]
        let ms = parts.count > 1 ? (Double(parts[1]) ?? 0) / 1000.0 : 0
        let comps = timePart.split(separator: ":")
        var secs = 0.0
        if comps.count == 3 {
            secs = (Double(comps[0]) ?? 0) * 3600 + (Double(comps[1]) ?? 0) * 60 + (Double(comps[2]) ?? 0)
        } else if comps.count == 2 {
            secs = (Double(comps[0]) ?? 0) * 60 + (Double(comps[1]) ?? 0)
        }
        return secs + ms
    }

    static func currentText(cues: [SubtitleCue], time: Double) -> String? {
        cues.first { time >= $0.start && time <= $0.end }?.text
    }
}
