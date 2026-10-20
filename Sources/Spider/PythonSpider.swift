import Foundation

@MainActor
final class PythonSpider: Spider {
    private let scriptPath: String

    init(scriptPath: String) {
        self.scriptPath = scriptPath
    }

    init(source: String) throws {
        // Write source to a temp file
        let dir = FileManager.default.temporaryDirectory
        let file = dir.appendingPathComponent("spider_\(UUID().uuidString).py")
        try source.write(to: file, atomically: true, encoding: .utf8)
        self.scriptPath = file.path
    }

    private func run(function: String, args: [Any]) async throws -> Any {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        var argv = [scriptPath, function]
        if let data = try? JSONSerialization.data(withJSONObject: args),
           let str = String(data: data, encoding: .utf8) {
            argv.append(str)
        }
        proc.arguments = argv
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        if let str = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !str.isEmpty,
           let obj = try? JSONSerialization.jsonObject(with: Data(str.utf8)) {
            return obj
        }
        throw SpiderError.decodeFailed
    }

    func home() async throws -> HomeResult {
        let obj = try await run(function: "home", args: [])
        var hr = HomeResult()
        if let dict = obj as? [String: Any] {
            if let classes = dict["class"] as? [[String: Any]] {
                hr.classes = classes.compactMap { c in
                    let id = (c["type_id"] as? String) ?? (c["type_id"] as? Int).map(String.init)
                    guard let id, let name = c["type_name"] as? String else { return nil }
                    return VodClass(id: id, name: name)
                }
            }
            if let list = dict["list"] {
                hr.list = decodeVods(list)
            }
        } else if let arr = obj as? [[String: Any]] {
            hr.list = arr.compactMap { decodeVod($0) }
        }
        return hr
    }

    func category(_ type: String, page: Int, filters: [String: String]) async throws -> (list: [Vod], total: Int) {
        let obj = try await run(function: "category", args: [type, page, filters])
        guard let dict = obj as? [String: Any] else { return ([], 0) }
        let list = decodeVods(dict["list"])
        let total = (dict["total"] as? Int) ?? list.count
        return (list, total)
    }

    func detail(_ ids: [String]) async throws -> [Vod] {
        let obj = try await run(function: "detail", args: [ids])
        return decodeVodList(obj)
    }

    func search(_ keyword: String, quick: Bool) async throws -> [Vod] {
        let obj = try await run(function: "search", args: [keyword, quick])
        return decodeVodList(obj)
    }

    func play(_ flag: String, url: String) async throws -> (url: String, headers: [String: String], subtitles: [String]) {
        let obj = try await run(function: "play", args: [flag, url])
        guard let dict = obj as? [String: Any] else { return (url, [:], []) }
        let playUrl = (dict["url"] as? String) ?? url
        let headers = (dict["header"] as? [String: String]) ?? [:]
        let subs = (dict["subtitle"] as? [String]) ?? []
        return (playUrl, headers, subs)
    }

    private func decodeVods(_ any: Any?) -> [Vod] {
        guard let arr = any as? [[String: Any]] else { return [] }
        return arr.compactMap { decodeVod($0) }
    }

    private func decodeVodList(_ obj: Any) -> [Vod] {
        if let dict = obj as? [String: Any], let list = dict["list"] {
            return decodeVods(list)
        }
        if let arr = obj as? [[String: Any]] {
            return arr.compactMap { decodeVod($0) }
        }
        return []
    }

    private func decodeVod(_ dict: [String: Any]) -> Vod? {
        var v = Vod()
        v.vodId = dict["vod_id"] as? String ?? dict["id"] as? String
        v.vodName = dict["vod_name"] as? String ?? dict["name"] as? String
        v.vodPic = dict["vod_pic"] as? String ?? dict["pic"] as? String
        v.vodRemarks = dict["vod_remarks"] as? String ?? dict["remarks"] as? String
        v.vodPlayFrom = dict["vod_play_from"] as? String
        v.vodPlayUrl = dict["vod_play_url"] as? String
        return v
    }
}
