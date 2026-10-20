import Foundation

@MainActor
final class FongMiPythonSpider: Spider {
    private let workDir: URL
    private let scriptFile: URL
    private let baseDir: URL

    init(source: String) throws {
        let tmp = FileManager.default.temporaryDirectory
        workDir = tmp.appendingPathComponent("fm_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        // base package
        baseDir = workDir.appendingPathComponent("base", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        try "".write(to: baseDir.appendingPathComponent("__init__.py"), atomically: true, encoding: .utf8)
        let shim = """
        import json
        class Spider:
            def getName(self):
                return ''
            def init(self, extend=''):
                pass
            def homeContent(self, filter):
                return {}
            def categoryContent(self, tid, pg, filter, extend):
                return {}
            def detailContent(self, ids):
                return {}
            def searchContent(self, key, quick):
                return {}
            def playerContent(self, flag, id, vipFlags):
                return {}
            def isVideoFormat(self, url):
                return False
            def manualVideoCheck(self):
                return
            def destroy(self):
                return
            def localProxy(self, param):
                return None
        """
        try shim.write(to: baseDir.appendingPathComponent("spider.py"), atomically: true, encoding: .utf8)
        scriptFile = workDir.appendingPathComponent("user_spider.py")
        try source.write(to: scriptFile, atomically: true, encoding: .utf8)
    }

    deinit {
        try? FileManager.default.removeItem(at: workDir)
    }

    private func run(method: String, args: [Any]) async throws -> [String: Any] {
        // Write runner
        let runner = workDir.appendingPathComponent("runner.py")
        let runnerCode = """
        import sys, json, os
        sys.path.insert(0, \(workDir.path.asPythonLiteral()))
        from user_spider import Spider as UserSpider
        sp = UserSpider()
        try:
            sp.init('')
        except Exception as e:
            pass
        method = sys.argv[1]
        args = json.loads(sys.argv[2]) if len(sys.argv) > 2 else []
        if method == 'home':
            res = sp.homeContent(args[0] if args else False)
        elif method == 'category':
            tid = args[0]; pg = args[1]; filt = args[2] if len(args)>2 else {}
            res = sp.categoryContent(tid, pg, filt, '')
        elif method == 'detail':
            res = sp.detailContent(args[0])
        elif method == 'search':
            key = args[0]; quick = args[1] if len(args)>1 else False
            res = sp.searchContent(key, quick)
        elif method == 'play':
            flag = args[0]; url = args[1]
            res = sp.playerContent(flag, url, [])
        else:
            res = {}
        print(json.dumps(res, ensure_ascii=False))
        """
        try runnerCode.write(to: runner, atomically: true, encoding: .utf8)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = [runner.path, method, (try? String(data: JSONSerialization.data(withJSONObject: args), encoding: .utf8)) ?? "[]"]
        proc.currentDirectoryURL = workDir
        let outPipe = Pipe(); let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        if let err = String(data: errData, encoding: .utf8), !err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("FM python stderr: \(err)")
        }
        guard let str = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty else {
            throw SpiderError.decodeFailed
        }
        if let data = str.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        throw SpiderError.decodeFailed
    }

    func home() async throws -> HomeResult {
        let obj = try await run(method: "home", args: [false])
        var hr = HomeResult()
        if let classes = obj["class"] as? [[String: Any]] {
            hr.classes = classes.compactMap { c in
                let id = (c["type_id"] as? String) ?? (c["type_id"] as? Int).map(String.init)
                guard let id, let name = c["type_name"] as? String else { return nil }
                return VodClass(id: id, name: name)
            }
        }
        if let list = obj["list"] {
            hr.list = decodeVods(list)
        }
        return hr
    }

    func category(_ type: String, page: Int, filters: [String: String]) async throws -> (list: [Vod], total: Int) {
        let obj = try await run(method: "category", args: [type, page, filters])
        let list = decodeVods(obj["list"])
        let total = (obj["total"] as? Int) ?? list.count
        return (list, total)
    }

    func detail(_ ids: [String]) async throws -> [Vod] {
        let obj = try await run(method: "detail", args: [ids])
        return decodeVods(obj["list"])
    }

    func search(_ keyword: String, quick: Bool) async throws -> [Vod] {
        let obj = try await run(method: "search", args: [keyword, quick])
        return decodeVods(obj["list"])
    }

    func play(_ flag: String, url: String) async throws -> (url: String, headers: [String: String], subtitles: [String]) {
        let obj = try await run(method: "play", args: [flag, url])
        // FongMi playerContent returns parse/url/header or url list
        if let playUrl = obj["url"] as? String {
            let headers = (obj["header"] as? [String: String]) ?? [:]
            return (playUrl, headers, [])
        }
        // Some return {"urls": [...]}
        if let urls = obj["urls"] as? [[String: Any]], let first = urls.first, let u = first["url"] as? String {
            return (u, [:], [])
        }
        return (url, [:], [])
    }

    private func decodeVods(_ any: Any?) -> [Vod] {
        guard let arr = any as? [[String: Any]] else { return [] }
        return arr.compactMap { decodeVod($0) }
    }

    private func decodeVod(_ dict: [String: Any]) -> Vod? {
        var v = Vod()
        v.vodId = dict["vod_id"] as? String ?? dict["id"] as? String
        v.vodName = dict["vod_name"] as? String ?? dict["name"] as? String
        v.vodPic = dict["vod_pic"] as? String ?? dict["pic"] as? String
        v.vodRemarks = dict["vod_remarks"] as? String
        v.vodPlayFrom = dict["vod_play_from"] as? String
        v.vodPlayUrl = dict["vod_play_url"] as? String
        return v
    }
}

private extension String {
    func asPythonLiteral() -> String {
        return "'" + self.replacingOccurrences(of: "\\", with: "\\\\") + "'"
    }
}
