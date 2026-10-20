import Foundation

struct AnyCodable: Codable {
    let value: Any
    init(_ value: Any) { self.value = value }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { value = v }
        else if let v = try? container.decode(Int.self) { value = v }
        else if let v = try? container.decode(Double.self) { value = v }
        else if let v = try? container.decode(Bool.self) { value = v }
        else if let v = try? container.decode([String: AnyCodable].self) { value = v.mapValues { $0.value } }
        else if let v = try? container.decode([AnyCodable].self) { value = v.map { $0.value } }
        else { value = NSNull() }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as String: try container.encode(v)
        case let v as Int: try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as Bool: try container.encode(v)
        default: try container.encodeNil()
        }
    }
}


/// Top-level FongMi config (vod config). Mirrors Config bean type 0.
struct AppConfig: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String?
    var url: String?
    var spider: String?
    var wallpaper: String?
    var logo: String?
    var notice: String?
    var sites: [Site] = []
    var parses: [ParseRule] = []
    var lives: [LiveConfig] = []
    var doh: [Doh] = []
    var proxy: [ProxyRule] = []
    var rules: [Rule] = []
    var headers: [HeaderRule] = []
    var hosts: [String] = []
    var flags: [String] = []
    var ads: [String] = []

    enum CodingKeys: String, CodingKey {
        case name, url, spider, wallpaper, logo, notice, sites, parses, lives, doh, proxy, rules, headers, hosts, flags, ads
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        spider = try c.decodeIfPresent(String.self, forKey: .spider)
        wallpaper = try c.decodeIfPresent(String.self, forKey: .wallpaper)
        logo = try c.decodeIfPresent(String.self, forKey: .logo)
        notice = try c.decodeIfPresent(String.self, forKey: .notice)
        sites = (try? c.decode([Site].self, forKey: .sites)) ?? []
        parses = (try? c.decode([ParseRule].self, forKey: .parses)) ?? []
        lives = (try? c.decode([LiveConfig].self, forKey: .lives)) ?? []
        doh = (try? c.decode([Doh].self, forKey: .doh)) ?? []
        proxy = (try? c.decode([ProxyRule].self, forKey: .proxy)) ?? []
        rules = (try? c.decode([Rule].self, forKey: .rules)) ?? []
        headers = (try? c.decode([HeaderRule].self, forKey: .headers)) ?? []
        hosts = (try? c.decode([String].self, forKey: .hosts)) ?? []
        flags = (try? c.decode([String].self, forKey: .flags)) ?? []
        ads = (try? c.decode([String].self, forKey: .ads)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(spider, forKey: .spider)
        try c.encodeIfPresent(wallpaper, forKey: .wallpaper)
        try c.encodeIfPresent(logo, forKey: .logo)
        try c.encodeIfPresent(notice, forKey: .notice)
        try c.encode(sites, forKey: .sites)
        try c.encode(parses, forKey: .parses)
        try c.encode(lives, forKey: .lives)
        try c.encode(doh, forKey: .doh)
        try c.encode(proxy, forKey: .proxy)
        try c.encode(rules, forKey: .rules)
        try c.encode(headers, forKey: .headers)
        try c.encode(hosts, forKey: .hosts)
        try c.encode(flags, forKey: .flags)
        try c.encode(ads, forKey: .ads)
    }
}

struct Site: Codable, Identifiable, Hashable {
    var id: String { key }
    var key: String
    var name: String
    var type: Int?
    var api: String?
    var searchable: Int?
    var quickSearch: Int?
    var filterable: Int?
    var changeable: Int?
    var ext: String?        // normalized to JSON string or raw
    var jar: String?
    var playerUrl: String?
    var playerType: Int?
    var categories: [String]?
    var style: Style?

    enum CodingKeys: String, CodingKey {
        case key, name, type, api, searchable, quickSearch, filterable, changeable, ext, jar, playerUrl, playerType, categories, style
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decodeIfPresent(Int.self, forKey: .type)
        api = try c.decodeIfPresent(String.self, forKey: .api)
        searchable = try c.decodeIfPresent(Int.self, forKey: .searchable)
        quickSearch = try c.decodeIfPresent(Int.self, forKey: .quickSearch)
        filterable = try c.decodeIfPresent(Int.self, forKey: .filterable)
        changeable = try c.decodeIfPresent(Int.self, forKey: .changeable)
        jar = try c.decodeIfPresent(String.self, forKey: .jar)
        playerUrl = try c.decodeIfPresent(String.self, forKey: .playerUrl)
        playerType = try c.decodeIfPresent(Int.self, forKey: .playerType)
        categories = try c.decodeIfPresent([String].self, forKey: .categories)
        style = try c.decodeIfPresent(Style.self, forKey: .style)
        // ext can be String or object
        if let s = try? c.decode(String.self, forKey: .ext) {
            ext = s
        } else if let obj = try? c.decode([String: AnyCodable].self, forKey: .ext) {
            let dict = obj.mapValues { $0.value }
            if let data = try? JSONSerialization.data(withJSONObject: dict) {
                ext = String(data: data, encoding: .utf8)
            } else {
                ext = nil
            }
        } else {
            ext = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(type, forKey: .type)
        try c.encodeIfPresent(api, forKey: .api)
        try c.encodeIfPresent(searchable, forKey: .searchable)
        try c.encodeIfPresent(quickSearch, forKey: .quickSearch)
        try c.encodeIfPresent(filterable, forKey: .filterable)
        try c.encodeIfPresent(changeable, forKey: .changeable)
        try c.encodeIfPresent(ext, forKey: .ext)
        try c.encodeIfPresent(jar, forKey: .jar)
        try c.encodeIfPresent(playerUrl, forKey: .playerUrl)
        try c.encodeIfPresent(playerType, forKey: .playerType)
        try c.encodeIfPresent(categories, forKey: .categories)
        try c.encodeIfPresent(style, forKey: .style)
    }
}

struct Style: Codable, Hashable {
    var type: String?
    var ratio: Double?
}

struct ParseRule: Codable, Identifiable {
    var id: String { name ?? UUID().uuidString }
    var name: String?
    var type: Int?
    var url: String?
    var ext: [String]?
}

struct LiveConfig: Codable, Identifiable {
    var id: String { name ?? UUID().uuidString }
    var name: String?
    var url: String?
    var epg: String?
    var logo: String?
    var group: String?
}

struct Doh: Codable { var name: String?; var url: String?; var ips: [String]? }
struct ProxyRule: Codable { var host: String?; var url: String? }
struct Rule: Codable { var host: String?; var regex: String?; var script: String? }
struct HeaderRule: Codable { var host: String?; var headers: [String: String]? }

struct Vod: Codable, Identifiable, Hashable {
    var id: String { vodId ?? UUID().uuidString }
    var vodId: String?
    var vodName: String?
    var vodPic: String?
    var vodRemarks: String?
    var vodYear: String?
    var vodArea: String?
    var vodActor: String?
    var vodDirector: String?
    var vodContent: String?
    var vodPlayFrom: String?
    var vodPlayUrl: String?
    var typeName: String?
    var typePid: Int?

    enum CodingKeys: String, CodingKey {
        case vodId = "vod_id"
        case vodName = "vod_name"
        case vodPic = "vod_pic"
        case vodRemarks = "vod_remarks"
        case vodYear = "vod_year"
        case vodArea = "vod_area"
        case vodActor = "vod_actor"
        case vodDirector = "vod_director"
        case vodContent = "vod_content"
        case vodPlayFrom = "vod_play_from"
        case vodPlayUrl = "vod_play_url"
        case typeName = "type_name"
        case typePid = "type_pid"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vodId = Self.flexString(c, key: .vodId)
        vodName = try c.decodeIfPresent(String.self, forKey: .vodName)
        vodPic = try c.decodeIfPresent(String.self, forKey: .vodPic)
        vodRemarks = try c.decodeIfPresent(String.self, forKey: .vodRemarks)
        vodYear = Self.flexString(c, key: .vodYear)
        vodArea = try c.decodeIfPresent(String.self, forKey: .vodArea)
        vodActor = try c.decodeIfPresent(String.self, forKey: .vodActor)
        vodDirector = try c.decodeIfPresent(String.self, forKey: .vodDirector)
        vodContent = try c.decodeIfPresent(String.self, forKey: .vodContent)
        vodPlayFrom = try c.decodeIfPresent(String.self, forKey: .vodPlayFrom)
        vodPlayUrl = try c.decodeIfPresent(String.self, forKey: .vodPlayUrl)
        typeName = try c.decodeIfPresent(String.self, forKey: .typeName)
        typePid = try c.decodeIfPresent(Int.self, forKey: .typePid)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(vodId, forKey: .vodId)
        try c.encodeIfPresent(vodName, forKey: .vodName)
        try c.encodeIfPresent(vodPic, forKey: .vodPic)
        try c.encodeIfPresent(vodRemarks, forKey: .vodRemarks)
        try c.encodeIfPresent(vodYear, forKey: .vodYear)
        try c.encodeIfPresent(vodArea, forKey: .vodArea)
        try c.encodeIfPresent(vodActor, forKey: .vodActor)
        try c.encodeIfPresent(vodDirector, forKey: .vodDirector)
        try c.encodeIfPresent(vodContent, forKey: .vodContent)
        try c.encodeIfPresent(vodPlayFrom, forKey: .vodPlayFrom)
        try c.encodeIfPresent(vodPlayUrl, forKey: .vodPlayUrl)
        try c.encodeIfPresent(typeName, forKey: .typeName)
        try c.encodeIfPresent(typePid, forKey: .typePid)
    }

    private static func flexString(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> String? {
        if let s = try? c.decode(String.self, forKey: key) { return s }
        if let i = try? c.decode(Int.self, forKey: key) { return String(i) }
        if let d = try? c.decode(Double.self, forKey: key) { return String(Int(d)) }
        return nil
    }
}

struct Episode: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var url: String
}

struct LiveChannel: Codable, Identifiable, Hashable {
    var id: String { name ?? url ?? UUID().uuidString }
    var name: String?
    var url: String?
    var logo: String?
    var group: String?
    var epgId: String?
}

struct EpgProgram: Codable, Identifiable {
    var id = UUID()
    var channel: String?
    var title: String?
    var start: Date?
    var end: Date?
}
