import Foundation
import JavaScriptCore

struct VodClass: Identifiable, Hashable {
    let id: String
    let name: String
}

struct HomeResult {
    var classes: [VodClass] = []
    var list: [Vod] = []
}

/// Common spider contract mirroring CatVod spider methods (subset).
@MainActor
protocol Spider {
    func home() async throws -> HomeResult
    func category(_ type: String, page: Int, filters: [String: String]) async throws -> (list: [Vod], total: Int)
    func detail(_ ids: [String]) async throws -> [Vod]
    func search(_ keyword: String, quick: Bool) async throws -> [Vod]
    func play(_ flag: String, url: String) async throws -> (url: String, headers: [String: String], subtitles: [String])
}

/// JavaScript spider powered by JavaScriptCore. Expects a JS object with functions:
/// home, category, detail, search, play returning JSON strings.
@MainActor
final class JSSpider: Spider {
    private let context: JSContext
    private let source: String

    init(source: String) throws {
        self.source = source
        guard let ctx = JSContext() else { throw SpiderError.noContext }
        self.context = ctx
        ctx.exceptionHandler = { _, exc in
            if let e = exc { print("JS exception: \(e)") }
        }
        // Load source
        ctx.evaluateScript(source)
        if ctx.exception != nil {
            throw SpiderError.loadFailed
        }
    }

    func home() async throws -> HomeResult {
        guard let fn = context.objectForKeyedSubscript("home") else { throw SpiderError.missingFunction("home") }
        let result = fn.call(withArguments: [])
        var hr = HomeResult()
        let obj: [String: Any]? = {
            if let str = result?.toString(), let data = str.data(using: .utf8) {
                return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }
            return result?.toDictionary() as? [String: Any]
        }()
        if let obj {
            if let classes = obj["class"] as? [[String: Any]] {
                hr.classes = classes.compactMap { c in
                    let id = (c["type_id"] as? String) ?? (c["type_id"] as? Int).map(String.init)
                    guard let id, let name = c["type_name"] as? String else { return nil }
                    return VodClass(id: id, name: name)
                }
            }
            if let list = obj["list"] {
                hr.list = decodeVodsFromAny(list)
            }
            if hr.list.isEmpty {
                hr.list = try decodeVodList(result)
            }
            return hr
        }
        hr.list = try decodeVodList(result)
        return hr
    }

    func category(_ type: String, page: Int, filters: [String: String]) async throws -> (list: [Vod], total: Int) {
        guard let fn = context.objectForKeyedSubscript("category") else { throw SpiderError.missingFunction("category") }
        let result = fn.call(withArguments: [type, page, filters])
        let obj = try jsonObject(result)
        let list = try decodeVods(obj["list"])
        let total = (obj["total"] as? Int) ?? list.count
        return (list, total)
    }

    func detail(_ ids: [String]) async throws -> [Vod] {
        guard let fn = context.objectForKeyedSubscript("detail") else { throw SpiderError.missingFunction("detail") }
        let result = fn.call(withArguments: [ids])
        return try decodeVodList(result)
    }

    func search(_ keyword: String, quick: Bool) async throws -> [Vod] {
        guard let fn = context.objectForKeyedSubscript("search") else { throw SpiderError.missingFunction("search") }
        let result = fn.call(withArguments: [keyword, quick])
        return try decodeVodList(result)
    }

    func play(_ flag: String, url: String) async throws -> (url: String, headers: [String: String], subtitles: [String]) {
        guard let fn = context.objectForKeyedSubscript("play") else { throw SpiderError.missingFunction("play") }
        let result = fn.call(withArguments: [flag, url])
        let obj = try jsonObject(result)
        let playUrl = (obj["url"] as? String) ?? url
        let headers = (obj["header"] as? [String: String]) ?? [:]
        let subs = (obj["subtitle"] as? [String]) ?? []
        return (playUrl, headers, subs)
    }

    // MARK: - helpers

    private func decodeVodsFromAny(_ any: Any) -> [Vod] {
        guard let arr = any as? [[String: Any]] else { return [] }
        return arr.compactMap { decodeVod($0) }
    }

    private func decodeVodList(_ js: JSValue?) throws -> [Vod] {
        guard let js else { return [] }
        if let str = js.toString(), let data = str.data(using: .utf8) {
            // FongMi returns JSON string; try parse as {"list":[...]} or array
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let list = obj["list"] {
                return try decodeVods(list)
            }
            if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return arr.compactMap { decodeVod($0) }
            }
        }
        if let arr = js.toArray() as? [[String: Any]] {
            return arr.compactMap { decodeVod($0) }
        }
        return []
    }

    private func decodeVods(_ any: Any?) throws -> [Vod] {
        guard let arr = any as? [[String: Any]] else { return [] }
        return arr.compactMap { decodeVod($0) }
    }

    private func decodeVod(_ dict: [String: Any]) -> Vod? {
        var v = Vod()
        v.vodId = dict["vod_id"] as? String ?? dict["id"] as? String
        v.vodName = dict["vod_name"] as? String ?? dict["name"] as? String
        v.vodPic = dict["vod_pic"] as? String ?? dict["pic"] as? String
        v.vodRemarks = dict["vod_remarks"] as? String ?? dict["remarks"] as? String
        v.vodYear = dict["vod_year"] as? String
        v.vodArea = dict["vod_area"] as? String
        v.vodActor = dict["vod_actor"] as? String
        v.vodDirector = dict["vod_director"] as? String
        v.vodContent = dict["vod_content"] as? String
        v.vodPlayFrom = dict["vod_play_from"] as? String
        v.vodPlayUrl = dict["vod_play_url"] as? String
        v.typeName = dict["type_name"] as? String
        return v
    }

    private func jsonObject(_ js: JSValue?) throws -> [String: Any] {
        guard let js else { return [:] }
        if let str = js.toString(), let data = str.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        if let dict = js.toDictionary() as? [String: Any] { return dict }
        return [:]
    }
}

enum SpiderError: Error {
    case noContext
    case loadFailed
    case missingFunction(String)
    case decodeFailed
}
