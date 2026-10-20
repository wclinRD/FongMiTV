import Foundation
import Hummingbird
import CryptoKit

@MainActor
final class LocalHTTPServer: ObservableObject {
    @Published var isRunning = false
    @Published var port: Int = 9978
    @Published var lastError: String?

    private var runner: Task<Void, Never>?
    private let rootDir: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("FongMiTV", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func start() {
        guard !isRunning else { return }
        let port = self.port
        let root = self.rootDir
        runner = Task.detached {
            do {
                let router = Router()
                // ping
                router.get("/ping") { _, _ in "pong" }
                // media
                router.get("/media") { _, _ in
                    await MainActor.run { PlaybackState.shared.json }
                }
                // cache
                router.get("/cache") { req, _ in
                    let p = req.uri.queryParameters
                    let action = p.getFirst(name: "do") ?? ""
                    let rule = p.getFirst(name: "rule") ?? ""
                    let key = p.getFirst(name: "key") ?? ""
                    let fullKey = "cache_" + (rule.isEmpty ? "" : rule + "_") + key
                    if action == "get" {
                        return UserDefaults.standard.string(forKey: fullKey) ?? ""
                    }
                    if action == "set" {
                        let val = p.getFirst(name: "value") ?? ""
                        UserDefaults.standard.set(val, forKey: fullKey)
                    }
                    if action == "del" {
                        UserDefaults.standard.removeObject(forKey: fullKey)
                    }
                    return "ok"
                }
                // action
                router.get("/action") { req, _ in
                    let p = req.uri.queryParameters
                    let doParam = p.getFirst(name: "do") ?? ""
                    await MainActor.run {
                        Self.handleAction(doParam, params: p, root: root)
                    }
                    return "ok"
                }
                // file listing / serving
                router.get("/file") { req, _ in
                    let p = req.uri.queryParameters
                    let path = p.getFirst(name: "path") ?? ""
                    return Self.serveFile(path: path, root: root, req: req)
                }
                router.get("/file/*") { req, _ in
                    let path = String(req.uri.path.dropFirst("/file/".count))
                    return Self.serveFile(path: path, root: root, req: req)
                }
                // newFolder
                router.get("/newFolder") { req, _ in
                    let p = req.uri.queryParameters
                    let path = p.getFirst(name: "path") ?? ""
                    let name = p.getFirst(name: "name") ?? ""
                    let dir = root.appendingPathComponent(path, isDirectory: true)
                    let target = dir.appendingPathComponent(name, isDirectory: true)
                    try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                    return "ok"
                }
                // delFile / delFolder
                router.get("/delFile") { req, _ in Self.deletePath(req: req, root: root) }
                router.get("/delFolder") { req, _ in Self.deletePath(req: req, root: root) }
                // upload (POST)
                router.post("/upload") { req, _ in
                    return "ok"
                }
                // parse
                router.get("/parse") { req, _ in
                    let p = req.uri.queryParameters
                    let jxs = p.getFirst(name: "jxs") ?? ""
                    let url = p.getFirst(name: "url") ?? ""
                    let html = "<html><body><script>console.log('parse', '\(jxs)', '\(url)')</script></body></html>"
                    return Response(status: .ok, headers: [.contentType: "text/html"], body: .init(byteBuffer: .init(string: html)))
                }
                // image
                router.get("/image/*") { req, _ in
                    let name = String(req.uri.path.dropFirst("/image/".count))
                    // serve from root/image
                    let file = root.appendingPathComponent("image").appendingPathComponent(name)
                    if let data = try? Data(contentsOf: file) {
                        return Response(status: .ok, headers: [.contentType: "image/png"], body: .init(byteBuffer: .init(data: data)))
                    }
                    return Response(status: .notFound)
                }
                // proxy
                router.get("/proxy") { req, _ in
                    let p = req.uri.queryParameters
                    guard let target = p.getFirst(name: "url") ?? p.getFirst(name: "do") else {
                        return Response(status: .badRequest)
                    }
                    // If target is a URL, fetch it
                    if target.hasPrefix("http") {
                        if let url = URL(string: target), let (data, resp) = try? await URLSession.shared.data(from: url) {
                            let mime = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
                            return Response(status: .ok, headers: [.contentType: mime], body: .init(byteBuffer: .init(data: data)))
                        }
                    }
                    return Response(status: .badRequest)
                }

                let app = Application(router: router, configuration: .init(address: .hostname("0.0.0.0", port: port)))
                try await app.runService()
            } catch {
                await MainActor.run {
                    // store error
                }
            }
        }
        isRunning = true
    }

    func stop() {
        runner?.cancel()
        runner = nil
        isRunning = false
    }

    // MARK: - Action handling
    nonisolated static func handleAction(_ action: String, params: URI.QueryParameters, root: URL) {
        Task { @MainActor in
            switch action {
            case "push":
                if let url = params.getFirst(name: "url"), !url.isEmpty {
                    // notify app to push url to player
                    NotificationCenter.default.post(name: .init("FongPushURL"), object: url)
                }
            case "search":
                if let word = params.getFirst(name: "word"), !word.isEmpty {
                    NotificationCenter.default.post(name: .init("FongSearch"), object: word)
                }
            case "setting":
                if let text = params.getFirst(name: "text"), !text.isEmpty {
                    NotificationCenter.default.post(name: .init("FongSetting"), object: (text, params.getFirst(name: "name")))
                }
            case "control":
                if let type = params.getFirst(name: "type") {
                    switch type {
                    case "play": PlaybackState.shared.update(isPlaying: true)
                    case "pause": PlaybackState.shared.update(isPlaying: false)
                    default: break
                    }
                }
            case "danmaku":
                if let text = params.getFirst(name: "text"), !text.isEmpty {
                    NotificationCenter.default.post(name: .init("FongDanmaku"), object: text)
                }
            default: break
            }
        }
    }

    // MARK: - File serving
    nonisolated static func serveFile(path: String, root: URL, req: Request) -> Response {
        let rel = path.isEmpty ? "/" : path
        let file = root.appendingPathComponent(rel.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        // directory listing
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir), isDir.boolValue {
            // list
            let items = (try? FileManager.default.contentsOfDirectory(at: file, includingPropertiesForKeys: nil)) ?? []
            var arr: [[String: Any]] = []
            for item in items {
                var isD: ObjCBool = false
                FileManager.default.fileExists(atPath: item.path, isDirectory: &isD)
                let attrs = try? FileManager.default.attributesOfItem(atPath: item.path)
                let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                arr.append([
                    "name": item.lastPathComponent,
                    "path": "/" + item.path.replacingOccurrences(of: root.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                    "time": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: mtime)),
                    "dir": isD.boolValue ? 1 : 0
                ])
            }
            let obj: [String: Any] = ["parent": ".", "files": arr]
            if let data = try? JSONSerialization.data(withJSONObject: obj),
               let str = String(data: data, encoding: .utf8) {
                return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: .init(string: str)))
            }
            return Response(status: .internalServerError)
        }
        guard FileManager.default.fileExists(atPath: file.path) else {
            return Response(status: .notFound)
        }
        if let data = try? Data(contentsOf: file) {
            let mime = mimeType(for: file.pathExtension)
            return Response(status: .ok, headers: [.contentType: mime], body: .init(byteBuffer: .init(data: data)))
        }
        return Response(status: .internalServerError)
    }

    nonisolated static func deletePath(req: Request, root: URL) -> Response {
        let p = req.uri.queryParameters
        let path = p.getFirst(name: "path") ?? ""
        let target = root.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        try? FileManager.default.removeItem(at: target)
        return Response(status: .ok, body: .init(byteBuffer: .init(string: "ok")))
    }

    nonisolated static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html","htm": return "text/html"
        case "json": return "application/json"
        case "txt": return "text/plain"
        case "png": return "image/png"
        case "jpg","jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "mp4": return "video/mp4"
        case "m3u8": return "application/vnd.apple.mpegurl"
        case "ts": return "video/mp2t"
        case "css": return "text/css"
        case "js": return "application/javascript"
        default: return "application/octet-stream"
        }
    }
}

extension URI.QueryParameters {
    func getFirst(name: String) -> String? {
        // Hummingbird's queryParameters is a collection of (name,value)
        for (n, v) in self {
            if n == name { return v }
        }
        return nil
    }
}
