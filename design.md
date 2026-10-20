# FongMiTV macOS — Design Document

## 1. 目標
將 Android 專案 [FongMi/TV](https://github.com/FongMi/TV) 的功能移植為 **原生 macOS App**（SwiftUI + Swift 6），以 `/Users/wclin/openchamber/FongMiTV` 為專案根目錄。

## 2. 測試介面 (TV Interface)
- **Config URL**: `https://raw.githubusercontent.com/qist/tvbox/refs/heads/master/dianshi.json`（測試介面，原 `http://yingshi.fongmi.eu.org`）
- 用途：App 啟動後「載入配置」的預設測試來源；伺服器回傳 HTML 落地頁時，App 應顯示錯誤而非崩潰。
- 其他相關端點（來自 FongMi 官網）：
  - 壁紙：`http://img.fongmi.eu.org`
  - 解密：`http://ua.fongmi.eu.org/`
  - 下載：`http://down.fongmi.eu.org/`
  - 道 (DAO)：`http://dao.fongmi.eu.org/`

## 3. 技術選型
| 項目 | 選擇 |
|---|---|
| 語言/UI | Swift 6 / SwiftUI |
| 平台 | macOS 14+（後續可擴 iOS/tvOS） |
| 專案格式 | Xcode (.xcodeproj) via xcodegen |
| HTTP Server | Hummingbird 2.x |
| JS Spider | JavaScriptCore |
| Python Spider | subprocess 呼叫 python3（後續可改 PythonKit） |
| 媒體播放 | AVKit (AVPlayer) + 後續 mpv |
| 持久化 | SwiftData / JSON 檔案 |
| 網路 | URLSession + ATS 任意載入 |

## 4. 功能範圍（依 FongMi feature-content）
P0（MVP）:
- 配置載入與站點瀏覽（Config JSON、Site、分類、搜尋）
- 簡體轉繁體顯示（AppSettings toggle + String.traditionalized）
- 詳情頁 + 集數選擇
- 影片播放（AVPlayer、倍速、字幕載入）
- Spider JS 載入與呼叫

P1:
- 直播 + EPG（M3U/TXT/JSON）
- 本地 HTTP 伺服器完整路由（/action /file /media /proxy /cache /parse /image）
- 遠端控制 / 推送 / 同步

P2:
- DLNA 投放/接收
- Python Spider / JAR 載入
- 爬蟲測試頁
- 模組管理（mpv/Thunder）

## 5. 資料模型
- `AppConfig`, `Site`, `Style`, `ParseRule`, `LiveConfig`, `Doh`, `ProxyRule`, `Rule`, `HeaderRule`
- `Vod`, `Episode`, `LiveChannel`, `EpgProgram`

## 6. Spider 協定（Swift 版）
```
protocol Spider {
  func home() async throws -> [Vod]
  func category(_ type: String, page: Int, filters:) async throws -> (list, total)
  func detail(_ ids: [String]) async throws -> [Vod]
  func search(_ keyword: String, quick: Bool) async throws -> [Vod]
  func play(_ flag: String, url: String) async throws -> (url, headers, subtitles)
}
```
- JSSpider：JavaScriptCore 執行 JS，JS 端實作同名函式回傳 JSON 字串/物件。

## 7. 實作順序
1. ✅ 專案骨架 + 編譯
2. ✅ 基礎模型 + ConfigService + SiteService + JSSpider + HTTP Server + UI
3. ✅ MacCMS 直連站點瀏覽（分類、列表、搜尋、詳情）；Spider JS 來源載入仍待
4. ✅ 播放流程（AVPlayer，倍速/字幕待加強）
5. ⬜ 本地 HTTP 伺服器完整路由
6. ⬜ 直播 + EPG
7. ⬜ DLNA / Python / JAR

## 8. 風險
- `lib-*.aar` 為 Android 專有，macOS 端以 AVPlayer/mpv 替代。
- Spider Java JAR 無法直接在 macOS 執行，需改 JS/Python 或移除。
- 配置 URL 可能回傳 HTML（如測試介面），需優雅處理。
EOF
echo "written"