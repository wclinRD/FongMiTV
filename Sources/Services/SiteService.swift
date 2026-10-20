import Foundation

@MainActor
final class SiteService: ObservableObject {
    private var spiders: [String: Spider] = [:]

    private func isMacCMS(_ site: Site) -> Bool {
        (site.type == 0 || site.type == 1) && (site.api?.hasPrefix("http") == true)
    }

    func spider(for site: Site, jsSource: String? = nil) -> Spider? {
        if let s = spiders[site.key] { return s }
        if let src = jsSource, let spider = try? JSSpider(source: src) {
            spiders[site.key] = spider
            return spider
        }
        return nil
    }

    func home(site: Site, jsSource: String?) async throws -> HomeResult {
        if isMacCMS(site), let api = site.api {
            var hr = HomeResult()
            hr.classes = (try? await MacCMSClient.categories(api: api)) ?? []
            let (list, _) = (try? await MacCMSClient.list(api: api, type: nil, page: 1, keyword: nil)) ?? ([], 0)
            hr.list = list
            return hr
        }
        guard let sp = spider(for: site, jsSource: jsSource) else { throw SpiderError.loadFailed }
        return try await sp.home()
    }

    func category(site: Site, jsSource: String?, type: String, page: Int, filters: [String: String] = [:]) async throws -> (list: [Vod], total: Int) {
        if isMacCMS(site), let api = site.api {
            return try await MacCMSClient.list(api: api, type: type, page: page, keyword: nil)
        }
        guard let sp = spider(for: site, jsSource: jsSource) else { throw SpiderError.loadFailed }
        return try await sp.category(type, page: page, filters: filters)
    }

    func detail(site: Site, jsSource: String?, ids: [String]) async throws -> [Vod] {
        if isMacCMS(site), let api = site.api {
            return (try? await MacCMSClient.detail(api: api, ids: ids.joined(separator: ","))) ?? []
        }
        guard let sp = spider(for: site, jsSource: jsSource) else { throw SpiderError.loadFailed }
        return try await sp.detail(ids)
    }

    func search(site: Site, jsSource: String?, keyword: String, quick: Bool = false) async throws -> [Vod] {
        if isMacCMS(site), let api = site.api {
            let (list, _) = (try? await MacCMSClient.list(api: api, type: nil, page: 1, keyword: keyword)) ?? ([], 0)
            return list
        }
        guard let sp = spider(for: site, jsSource: jsSource) else { throw SpiderError.loadFailed }
        return try await sp.search(keyword, quick: quick)
    }

    func play(site: Site, jsSource: String?, flag: String, url: String) async throws -> (url: String, headers: [String: String], subtitles: [String]) {
        if isMacCMS(site) {
            return (url, [:], [])
        }
        guard let sp = spider(for: site, jsSource: jsSource) else { throw SpiderError.loadFailed }
        return try await sp.play(flag, url: url)
    }
}
