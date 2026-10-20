import Foundation

struct MacCMSResponse: Codable {
    var code: Int?
    var msg: String?
    var page: String?
    var pagecount: String?
    var total: String?
    var list: [Vod]?
    var classList: [MacCMSClass]?

    enum CodingKeys: String, CodingKey {
        case code, msg, page, pagecount, total, list
        case classList = "class"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decodeIfPresent(Int.self, forKey: .code)
        msg = try c.decodeIfPresent(String.self, forKey: .msg)
        page = Self.flexString(c, key: .page)
        pagecount = Self.flexString(c, key: .pagecount)
        total = Self.flexString(c, key: .total)
        list = try c.decodeIfPresent([Vod].self, forKey: .list)
        classList = try c.decodeIfPresent([MacCMSClass].self, forKey: .classList)
    }

    private static func flexString(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> String? {
        if let s = try? c.decode(String.self, forKey: key) { return s }
        if let i = try? c.decode(Int.self, forKey: key) { return String(i) }
        if let d = try? c.decode(Double.self, forKey: key) { return String(Int(d)) }
        return nil
    }
}

struct MacCMSClass: Codable {
    var typeId: Int?
    var typeName: String?
    enum CodingKeys: String, CodingKey {
        case typeId = "type_id"
        case typeName = "type_name"
    }
}

enum MacCMSClient {
    static func buildURL(api: String, params: [String: String]) -> URL? {
        var comps = URLComponents(string: api)
        var items = comps?.queryItems ?? []
        for (k,v) in params { items.append(URLQueryItem(name: k, value: v)) }
        comps?.queryItems = items
        return comps?.url
    }

    static func fetch(_ url: URL) async throws -> MacCMSResponse {
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(MacCMSResponse.self, from: data)
        } catch {
            throw error
        }
    }

    static func categories(api: String) async throws -> [VodClass] {
        // try ac=class
        if let url = buildURL(api: api, params: ["ac": "class"]) {
            if let resp = try? await fetch(url), let cls = resp.classList {
                return cls.compactMap { c in
                    guard let id = c.typeId, let name = c.typeName else { return nil }
                    return VodClass(id: String(id), name: name)
                }
            }
        }
        return []
    }

    static func list(api: String, type: String?, page: Int, keyword: String?) async throws -> (list: [Vod], total: Int) {
        var params: [String: String] = ["ac": "list", "pg": String(page)]
        if let type, !type.isEmpty, type != "0" { params["t"] = type }
        if let keyword, !keyword.isEmpty { params["wd"] = keyword }
        guard let url = buildURL(api: api, params: params) else { throw URLError(.badURL) }
        let resp = try await fetch(url)
        let totalInt = Int(resp.total ?? "0") ?? 0
        return (resp.list ?? [], totalInt)
    }

    static func detail(api: String, ids: String) async throws -> [Vod] {
        guard let url = buildURL(api: api, params: ["ac": "detail", "ids": ids]) else { throw URLError(.badURL) }
        let resp = try await fetch(url)
        return resp.list ?? []
    }
}
