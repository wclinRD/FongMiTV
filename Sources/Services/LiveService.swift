import Foundation

@MainActor
final class LiveService: ObservableObject {
    @Published var channels: [LiveChannel] = []
    @Published var epg: [String: [EpgProgram]] = [:]
    @Published var isLoading = false
    @Published var error: String?

    func load(from config: LiveConfig) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        guard let urlStr = config.url, let url = URL(string: urlStr) else {
            error = "Invalid URL"; return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let text = String(data: data, encoding: .utf8) ?? ""
            var parsed: [LiveChannel] = []
            if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") || text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                parsed = parseJSON(data)
            } else if text.contains("#EXTM3U") || text.contains("#EXTINF") {
                parsed = parseM3U(text)
            } else {
                parsed = parseTXT(text)
            }
            self.channels = parsed
            // EPG
            if let epgUrl = config.epg, let epgURL = URL(string: epgUrl) {
                await loadEpg(from: epgURL)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadEpg(from url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let text = String(data: data, encoding: .utf8) ?? ""
            if text.contains("<tv") {
                self.epg = parseXMLTV(text)
            } else if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") || text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                // JSON epg: {channel: [{title,start,end}]}
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    var result: [String: [EpgProgram]] = [:]
                    for (ch, val) in obj {
                        if let arr = val as? [[String: Any]] {
                            result[ch] = arr.compactMap { parseEpgJSON($0, channel: ch) }
                        }
                    }
                    self.epg = result
                }
            }
        } catch {
            // ignore epg errors
        }
    }

    // MARK: - M3U
    private func parseM3U(_ text: String) -> [LiveChannel] {
        var channels: [LiveChannel] = []
        var current: (name: String?, logo: String?, group: String?, epgId: String?) = (nil,nil,nil,nil)
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#EXTINF") {
                // parse attributes
                var name: String?
                var logo: String?
                var group: String?
                var epgId: String?
                // tvg-id
                if let r = trimmed.range(of: "tvg-id=\"", options: .caseInsensitive) {
                    let rest = trimmed[r.upperBound...]
                    if let end = rest.firstIndex(of: "\"") { epgId = String(rest[..<end]) }
                }
                if let r = trimmed.range(of: "tvg-logo=\"", options: .caseInsensitive) {
                    let rest = trimmed[r.upperBound...]
                    if let end = rest.firstIndex(of: "\"") { logo = String(rest[..<end]) }
                }
                if let r = trimmed.range(of: "group-title=\"", options: .caseInsensitive) {
                    let rest = trimmed[r.upperBound...]
                    if let end = rest.firstIndex(of: "\"") { group = String(rest[..<end]) }
                }
                // name after last comma
                if let comma = trimmed.lastIndex(of: ",") {
                    name = String(trimmed[trimmed.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
                }
                current = (name, logo, group, epgId)
            } else if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                let url = trimmed
                let ch = LiveChannel(name: current.name ?? url, url: url, logo: current.logo, group: current.group, epgId: current.epgId)
                channels.append(ch)
                current = (nil,nil,nil,nil)
            }
        }
        return channels
    }

    // MARK: - TXT (FongMi genre format)
    private func parseTXT(_ text: String) -> [LiveChannel] {
        var channels: [LiveChannel] = []
        var currentGroup: String?
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasSuffix(",#genre#") || trimmed.contains(",#genre#") {
                currentGroup = trimmed.replacingOccurrences(of: ",#genre#", with: "")
                continue
            }
            let parts = trimmed.split(separator: ",", maxSplits: 1)
            if parts.count == 2 {
                let name = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let url = String(parts[1]).trimmingCharacters(in: .whitespaces)
                if url.hasPrefix("http") {
                    channels.append(LiveChannel(name: name, url: url, logo: nil, group: currentGroup, epgId: nil))
                }
            }
        }
        return channels
    }

    // MARK: - JSON
    private func parseJSON(_ data: Data) -> [LiveChannel] {
        // Support array of objects or {channels:[...]} or {list:[...]}
        var arr: [[String: Any]] = []
        if let obj = try? JSONSerialization.jsonObject(with: data) {
            if let a = obj as? [[String: Any]] { arr = a }
            else if let d = obj as? [String: Any] {
                if let a = d["channels"] as? [[String: Any]] { arr = a }
                else if let a = d["list"] as? [[String: Any]] { arr = a }
                else if let a = d["lives"] as? [[String: Any]] { arr = a }
            }
        }
        return arr.compactMap { dict in
            let name = dict["name"] as? String ?? dict["title"] as? String
            let url = dict["url"] as? String ?? dict["link"] as? String
            guard let name, let url else { return nil }
            return LiveChannel(
                name: name,
                url: url,
                logo: dict["logo"] as? String,
                group: dict["group"] as? String ?? dict["group-title"] as? String,
                epgId: dict["epg"] as? String ?? dict["tvg-id"] as? String
            )
        }
    }

    // MARK: - XMLTV
    private func parseXMLTV(_ text: String) -> [String: [EpgProgram]] {
        let parser = XMLParser(data: text.data(using: .utf8) ?? Data())
        let delegate = XMLTVParserDelegate()
        parser.delegate = delegate
        parser.parse()
        return delegate.result
    }

    private func parseEpgJSON(_ dict: [String: Any], channel: String) -> EpgProgram? {
        var p = EpgProgram()
        p.channel = channel
        p.title = dict["title"] as? String ?? dict["name"] as? String
        if let s = dict["start"] as? String { p.start = parseDate(s) }
        if let e = dict["end"] as? String { p.end = parseDate(e) }
        return p
    }

    private func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyyMMddHHmmss Z", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}

// MARK: - XMLTV parser delegate
private class XMLTVParserDelegate: NSObject, XMLParserDelegate {
    var result: [String: [EpgProgram]] = [:]
    private var currentChannel: String?
    private var currentTitle: String?
    private var currentStart: String?
    private var currentStop: String?
    private var inTitle = false
    private var titleBuffer = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "programme" {
            currentChannel = attributeDict["channel"]
            currentStart = attributeDict["start"]
            currentStop = attributeDict["stop"]
            currentTitle = nil
            titleBuffer = ""
        } else if elementName == "title" {
            inTitle = true
            titleBuffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inTitle { titleBuffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "title" {
            inTitle = false
            currentTitle = titleBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if elementName == "programme" {
            let ch = currentChannel ?? ""
            var prog = EpgProgram()
            prog.channel = ch
            prog.title = currentTitle
            if let s = currentStart { prog.start = parseDateStatic(s) }
            if let e = currentStop { prog.end = parseDateStatic(e) }
            result[ch, default: []].append(prog)
        }
    }

    private func parseDateStatic(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyyMMddHHmmss Z", "yyyyMMddHHmmss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
