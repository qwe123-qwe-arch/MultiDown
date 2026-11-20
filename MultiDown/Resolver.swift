import Foundation
import WebKit

// MARK: - 解析结果模型

struct MediaItem: Identifiable {
    let id = UUID()
    var title: String
    var url: URL
    var headers: [String: String] = [:]
}

struct ResolveOutput {
    var platform: String
    var title: String
    var items: [MediaItem]
    var note: String?
}

enum ResolveError: LocalizedError {
    case unsupported(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let message): return message
        case .failed(let message): return message
        }
    }
}

// MARK: - 平台识别

enum PanPlatform: String {
    case direct = "直链"
    case douyin = "抖音"
    case kuaishou = "快手"
    case bilibili = "哔哩哔哩"
    case weibo = "微博"
    case xhs = "小红书"
    case pixiv = "Pixiv"
    case quark = "夸克网盘"
    case uc = "UC网盘"
    case baidu = "百度网盘"
    case pan123 = "123网盘"
    case lanzou = "蓝奏云"
    case thunder = "迅雷"
    case unknown = "未知"
}

struct ParsedLink {
    var platform: PanPlatform
    var url: URL?
    var shareID: String?
    var passcode: String?
    var text: String
}

enum LinkParser {

    static func parse(_ raw: String) -> ParsedLink {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = firstURL(in: text)
        let url = urlString.flatMap { URL(string: $0) }
        let host = url?.host?.lowercased() ?? ""

        let platform: PanPlatform
        switch true {
        case host.contains("douyin") || host.contains("iesdouyin"): platform = .douyin
        case host.contains("kuaishou") || host.contains("kwai"): platform = .kuaishou
        case host.contains("bilibili") || host.contains("b23.tv"): platform = .bilibili
        case host.contains("weibo"): platform = .weibo
        case host.contains("xiaohongshu") || host.contains("xhslink"): platform = .xhs
        case host.contains("pixiv"): platform = .pixiv
        case host.contains("quark"): platform = .quark
        case host.contains("uc.cn") || host.contains("drive.uc"): platform = .uc
        case host.contains("baidu"): platform = .baidu
        case host.contains("123pan") || host.contains("123684"): platform = .pan123
        case host.contains("lanzou") || host.contains("lanrar") || host.contains("lanzn"): platform = .lanzou
        case host.contains("xunlei") || host.contains("thunder"): platform = .thunder
        case url != nil: platform = .direct
        default: platform = .unknown
        }

        return ParsedLink(platform: platform, url: url, shareID: shareID(from: url), passcode: passcode(from: text, url: url), text: text)
    }

    static func firstURL(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        for match in matches {
            if let url = match.url { return url.absoluteString }
        }
        return text.firstMatch("(https?://[^\\s\u{3000}]+)")
    }

    static func shareID(from url: URL?) -> String? {
        guard let url = url else { return nil }
        let path = url.path
        if let id = path.firstMatch("/s/([A-Za-z0-9_-]+)") { return id }
        let last = path.split(separator: "/").last.map(String.init)
        return last?.isEmpty == false ? last : nil
    }

    static func passcode(from text: String, url: URL?) -> String? {
        if let code = text.firstMatch("(?:提取码|密码|口令|pwd|code)\\s*[:：=]?\\s*([0-9A-Za-z]{4})") {
            return code
        }
        if let url = url,
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let pwd = components.queryItems?.first(where: { $0.name.lowercased() == "pwd" })?.value {
            return pwd
        }
        return nil
    }
}

// MARK: - 小工具

extension String {
    func firstMatch(_ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let ns = self as NSString
        guard let match = regex.firstMatch(in: self, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        if match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: self) {
            return String(self[range])
        }
        return nil
    }

    var unescapedJSON: String {
        replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
    }
}

func dig(_ any: Any?, _ path: [Any]) -> Any? {
    var current = any
    for key in path {
        if let name = key as? String, let dict = current as? [String: Any] {
            current = dict[name]
        } else if let index = key as? Int, let array = current as? [Any], index < array.count {
            current = array[index]
        } else {
            return nil
        }
    }
    return current
}

enum Http {
    static let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
    static let mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"

    @discardableResult
    static func request(_ url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil, userAgent: String = mobileUA) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let body = body {
            request.httpBody = body
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ResolveError.failed("服务器没有返回 HTTP 响应")
        }
        return (data, http)
    }

    static func string(_ url: URL, headers: [String: String] = [:], userAgent: String = mobileUA) async throws -> String {
        let (data, http) = try await request(url, headers: headers, userAgent: userAgent)
        guard (200...399).contains(http.statusCode) else {
            throw ResolveError.failed("HTTP \(http.statusCode)")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func json(_ url: URL, method: String = "GET", headers: [String: String] = [:], body: [String: Any]? = nil, userAgent: String = mobileUA) async throws -> Any {
        var requestHeaders = headers
        var data: Data?
        if let body = body {
            data = try JSONSerialization.data(withJSONObject: body)
            if requestHeaders["Content-Type"] == nil { requestHeaders["Content-Type"] = "application/json" }
        }
        let (responseData, http) = try await request(url, method: method, headers: requestHeaders, body: data, userAgent: userAgent)
        guard (200...299).contains(http.statusCode) else {
            throw ResolveError.failed("HTTP \(http.statusCode)")
        }
        return (try? JSONSerialization.jsonObject(with: responseData)) ?? [:]
    }
}

enum CookieJar {
    static func header(for url: URL) async -> String {
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        let host = url.host ?? ""
        let matched = cookies.filter { cookie in
            let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host.contains(domain) || domain.contains(host)
        }
        return matched.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}

// MARK: - 解析入口

enum LinkResolver {

    static func resolve(_ raw: String) async throws -> ResolveOutput {
        let parsed = LinkParser.parse(raw)
        guard let url = parsed.url else {
            throw ResolveError.failed("没找到链接，把整段分享文本粘贴进来就行")
        }

        switch parsed.platform {
        case .direct: return try await direct(url, parsed: parsed)
        case .douyin: return try await douyin(url)
        case .kuaishou: return try await kuaishou(url)
        case .bilibili: return try await bilibili(url)
        case .weibo: return try await weibo(url)
        case .xhs: return try await xiaohongshu(url)
        case .pixiv: return try await pixiv(url)
        case .quark: return try await quark(url)
        case .uc: return try await uc(url)
        case .baidu: return try await baidu(url, parsed: parsed)
        case .lanzou: return try await lanzou(url)
        case .pan123: return try await pan123(url)
        case .thunder: throw ResolveError.unsupported("迅雷网盘需要客户端协议，暂不支持，复制直链可以直接下")
        case .unknown: throw ResolveError.failed("认不出这个链接属于哪个平台")
        }
    }

    static func direct(_ url: URL, parsed: ParsedLink) async throws -> ResolveOutput {
        let knownExtensions: Set<String> = ["mp4", "mov", "m4v", "mp3", "m4a", "zip", "7z", "rar", "pdf", "jpg", "png", "gif", "webp", "epub", "apk", "ipa"]
        let ext = url.pathExtension.lowercased()
        if knownExtensions.contains(ext) {
            let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
            return ResolveOutput(platform: parsed.platform.rawValue, title: name, items: [MediaItem(title: name, url: url)], note: nil)
        }

        if let html = try? await Http.string(url), html.isEmpty == false {
            let media = html.unescapedJSON.firstMatch("(https?://[^\"'\\\\s]+?\\.(?:mp4|m3u8|mov)[^\"'\\\\s]*)")
            if let mediaString = media, let mediaURL = URL(string: mediaString) {
                let title = html.firstMatch("<title>([^<]+)</title>") ?? "网页视频"
                let headers = ["Referer": url.absoluteString, "User-Agent": Http.mobileUA]
                return ResolveOutput(platform: parsed.platform.rawValue, title: title, items: [MediaItem(title: title, url: mediaURL, headers: headers)], note: "从网页里抓到的直链")
            }
        }
        let name = url.lastPathComponent
        return ResolveOutput(platform: parsed.platform.rawValue, title: name, items: [MediaItem(title: name, url: url)], note: "按直链处理，如果失败可能是需要登录或防盗链")
    }

    static func douyin(_ url: URL) async throws -> ResolveOutput {
        var current = url
        for _ in 0..<6 {
            guard let (_, http) = try? await Http.request(current) else { break }
            if let location = http.value(forHTTPHeaderField: "Location"), let next = URL(string: location, relativeTo: current) {
                current = next.absoluteURL
            } else {
                break
            }
        }
        let id = current.absoluteString.firstMatch("/video/(\\d+)")
            ?? current.absoluteString.firstMatch("modal_id=(\\d+)")
            ?? url.absoluteString.firstMatch("/video/(\\d+)")
        guard let awemeID = id else { throw ResolveError.failed("没认出抖音视频 ID，试试直接粘贴完整分享文本") }

        if let object = try? await Http.json(URL(string: "https://www.iesdouyin.com/web/api/v2/aweme/iteminfo/?item_ids=\(awemeID)")!, headers: ["Referer": "https://www.douyin.com/"]),
           let list = dig(object, ["item_list"]) as? [Any],
           let first = list.first,
           let playList = dig(first, ["video", "play_addr", "url_list"]) as? [String],
           let play = playList.first {
            let clean = play.replacingOccurrences(of: "playwm", with: "play")
            let title = (dig(first, ["desc"]) as? String) ?? "抖音视频"
            return ResolveOutput(platform: "抖音", title: title, items: [MediaItem(title: title, url: URL(string: clean) ?? url, headers: ["Referer": "https://www.douyin.com/", "User-Agent": Http.mobileUA])], note: nil)
        }

        let page = try await Http.string(URL(string: "https://www.douyin.com/video/\(awemeID)")!, headers: ["Referer": "https://www.douyin.com/"])
        guard let raw = page.unescapedJSON.firstMatch("\"playAddr\":\"([^\"]+)\"") ?? page.unescapedJSON.firstMatch("\"url_list\":[\"](https?:[^\"]+)"),
              let mediaURL = URL(string: raw.replacingOccurrences(of: "playwm", with: "play")) else {
            throw ResolveError.failed("抖音解析失败，可能需要登录或接口已变")
        }
        return ResolveOutput(platform: "抖音", title: "抖音视频", items: [MediaItem(title: "抖音视频", url: mediaURL, headers: ["Referer": "https://www.douyin.com/"])], note: nil)
    }

    static func kuaishou(_ url: URL) async throws -> ResolveOutput {
        let page = try await Http.string(url, headers: ["Referer": "https://www.kuaishou.com/"])
        let candidates = [
            page.unescapedJSON.firstMatch("\"srcNoMark\":\"([^\"]+)\""),
            page.unescapedJSON.firstMatch("\"playUrl\":\"([^\"]+)\""),
            page.unescapedJSON.firstMatch("\"photoUrl\":\"([^\"]+)\"")
        ]
        guard let raw = candidates.compactMap({ $0 }).first, let mediaURL = URL(string: raw) else {
            throw ResolveError.failed("快手解析失败（可能需要登录或接口已变）")
        }
        let title = page.firstMatch("<title>([^<]+)</title>") ?? "快手视频"
        return ResolveOutput(platform: "快手", title: title, items: [MediaItem(title: title, url: mediaURL, headers: ["Referer": "https://www.kuaishou.com/"])], note: nil)
    }

    static func bilibili(_ url: URL) async throws -> ResolveOutput {
        let text = url.absoluteString
        guard let bv = text.firstMatch("(BV[0-9A-Za-z]{10})") else { throw ResolveError.failed("没认出 BV 号") }
        let api = URL(string: "https://api.bilibili.com/x/web-interface/view?bvid=\(bv)")!
        let view = try await Http.json(api, headers: ["Referer": "https://www.bilibili.com/"])
        guard let cid = dig(view, ["data", "cid"]) as? Int else { throw ResolveError.failed("B 站接口返回异常") }
        let title = (dig(view, ["data", "title"]) as? String) ?? "B 站视频"
        let playURL = URL(string: "https://api.bilibili.com/x/player/playurl?bvid=\(bv)&cid=\(cid)&qn=64&fnval=0&fnarg=0&fourk=1")!
        let play = try await Http.json(playURL, headers: ["Referer": "https://www.bilibili.com/"])
        guard let durl = dig(play, ["data", "durl"]) as? [Any], let first = durl.first, let raw = dig(first, ["url"]) as? String, let mediaURL = URL(string: raw) else {
            throw ResolveError.failed("B 站没有返回可下载的 mp4（番剧/大会员内容需要登录）")
        }
        return ResolveOutput(platform: "哔哩哔哩", title: title, items: [MediaItem(title: title, url: mediaURL, headers: ["Referer": "https://www.bilibili.com/", "User-Agent": Http.desktopUA])], note: "非大会员清晰度；DASH 超清需要另外合并音轨")
    }

    static func weibo(_ url: URL) async throws -> ResolveOutput {
        let page = try await Http.string(url, headers: ["Referer": "https://weibo.com/"])
        let raw = page.unescapedJSON.firstMatch("\"video_url\":\"([^\"]+)\"") ?? page.unescapedJSON.firstMatch("\"stream_url\":\"([^\"]+)\"")
        guard let value = raw, let mediaURL = URL(string: value) else {
            throw ResolveError.failed("微博没找到视频直链")
        }
        let title = page.firstMatch("<title>([^<]+)</title>") ?? "微博视频"
        return ResolveOutput(platform: "微博", title: title, items: [MediaItem(title: title, url: mediaURL, headers: ["Referer": "https://weibo.com/"])], note: nil)
    }

    static func xiaohongshu(_ url: URL) async throws -> ResolveOutput {
        let page = try await Http.string(url, headers: ["Referer": "https://www.xiaohongshu.com/"])
        let raw = page.unescapedJSON.firstMatch("\"masterUrl\":\"([^\"]+)\"") ?? page.unescapedJSON.firstMatch("\"url\":\"(http[^\"]+\\.mp4[^\"]*)\"$")
        guard let value = raw, let mediaURL = URL(string: value) else {
            throw ResolveError.failed("小红书需要登录态/签名，这个链接没解析出来")
        }
        let title = page.firstMatch("<title>([^<]+)</title>") ?? "小红书"
        return ResolveOutput(platform: "小红书", title: title, items: [MediaItem(title: title, url: mediaURL, headers: ["Referer": "https://www.xiaohongshu.com/"])], note: nil)
    }

    static func pixiv(_ url: URL) async throws -> ResolveOutput {
        let id = url.absoluteString.firstMatch("artworks/(\\d+)") ?? url.absoluteString.firstMatch("illust_id=(\\d+)")
        guard let illustID = id else { throw ResolveError.failed("没认出 Pixiv 作品 ID") }
        let api = URL(string: "https://www.pixiv.net/ajax/illust/\(illustID)")!
        let object = try await Http.json(api, headers: ["Referer": "https://www.pixiv.net/"])
        guard let raw = dig(object, ["body", "urls", "original"]) as? String, let mediaURL = URL(string: raw) else {
            throw ResolveError.failed("Pixiv 接口返回异常")
        }
        let title = (dig(object, ["body", "title"]) as? String) ?? "Pixiv \(illustID)"
        return ResolveOutput(platform: "Pixiv", title: title, items: [MediaItem(title: title, url: mediaURL, headers: ["Referer": "https://www.pixiv.net/"])], note: nil)
    }

    static func quark(_ url: URL) async throws -> ResolveOutput {
        try await cloudDrive(url: url, host: "drive.quark.cn", pr: "ucpro", referer: "https://pan.quark.cn", platform: "夸克网盘")
    }

    static func uc(_ url: URL) async throws -> ResolveOutput {
        try await cloudDrive(url: url, host: "drive.uc.cn", pr: "ucpro", referer: "https://drive.uc.cn", platform: "UC网盘")
    }

    static func cloudDrive(url: URL, host: String, pr: String, referer: String, platform: String) async throws -> ResolveOutput {
        let parsed = LinkParser.parse(url.absoluteString)
        guard let pwdID = parsed.shareID else { throw ResolveError.failed("没认出分享 ID") }

        let tokenURL = URL(string: "https://\(host)/1/clouddrive/share/sharepage/token?pr=\(pr)&fr=pc")!
        let tokenJSON = try await Http.json(tokenURL, method: "POST", headers: ["Referer": referer], body: ["pwd_id": pwdID, "passcode": parsed.passcode ?? ""])
        guard let stoken = dig(tokenJSON, ["data", "stoken"]) as? String else {
            let message = (dig(tokenJSON, ["message"]) as? String) ?? "分享可能已失效"
            throw ResolveError.failed("\(platform)：\(message)")
        }

        let detailURL = URL(string: "https://\(host)/1/clouddrive/share/sharepage/detail?pr=\(pr)&fr=pc&pwd_id=\(pwdID)&stoken=\(stoken)&pdir_fid=0&force=0&_page=1&_size=100&_fetch_banner=0&_fetch_share=0&_fetch_total=1")!
        let detail = try await Http.json(detailURL, headers: ["Referer": referer])
        guard let list = dig(detail, ["data", "list"]) as? [Any], !list.isEmpty else {
            throw ResolveError.failed("\(platform)：分享里没有文件")
        }

        let cookie = await CookieJar.header(for: URL(string: referer)!)
        var items: [MediaItem] = []
        var firstTitle = "\(platform)分享"

        for entry in list {
            guard let name = dig(entry, ["file_name"]) as? String,
                  let fid = dig(entry, ["fid"]) as? String else { continue }
            let isDir = (dig(entry, ["dir"]) as? Bool) ?? false
            let size = Int64((dig(entry, ["size"]) as? Int) ?? 0)
            if items.isEmpty { firstTitle = name }
            if isDir { continue }

            let shareToken = (dig(entry, ["share_fid_token"]) as? String) ?? ""
            let downloadURL = URL(string: "https://\(host)/1/clouddrive/share/sharepage/download?pr=\(pr)&fr=pc")!
            let body: [String: Any] = ["fid_list": [fid], "fid_token_list": [shareToken], "stoken": stoken]
            var headers: [String: String] = ["Referer": referer, "User-Agent": Http.desktopUA]
            if cookie.isEmpty == false { headers["Cookie"] = cookie }

            guard let json = try? await Http.json(downloadURL, method: "POST", headers: headers, body: body, userAgent: Http.desktopUA),
                  let raw = dig(json, ["data", 0, "download_url"]) as? String,
                  let mediaURL = URL(string: raw) else {
                if cookie.isEmpty {
                    throw ResolveError.failed("\(platform) 要登录才能拿下载地址：先去「网盘登录」里登录一次再解析")
                }
                continue
            }
            items.append(MediaItem(title: size > 0 ? "\(name)（\(ByteCounter.string(size))）" : name, url: mediaURL, headers: headers))
        }

        if items.isEmpty {
            throw ResolveError.failed("\(platform)：没取到可下载的文件（文件夹请先手动展开）")
        }
        return ResolveOutput(platform: platform, title: firstTitle, items: items, note: "下载需要保持登录态，链接有时效")
    }

    static func baidu(_ url: URL, parsed: ParsedLink) async throws -> ResolveOutput {
        let shareURL: URL
        if url.absoluteString.contains("/s/") {
            shareURL = url
        } else if let id = parsed.shareID {
            shareURL = URL(string: "https://pan.baidu.com/s/\(id)")!
        } else {
            throw ResolveError.failed("没认出百度分享 ID")
        }

        let cookie = await CookieJar.header(for: URL(string: "https://pan.baidu.com")!)
        var headers: [String: String] = ["Referer": "https://pan.baidu.com/", "User-Agent": Http.desktopUA]
        if cookie.isEmpty == false { headers["Cookie"] = cookie }

        let page = try await Http.string(shareURL, headers: headers, userAgent: Http.desktopUA)
        guard let shareID = page.firstMatch("\"shareid\":(\\d+)"),
              let uk = page.firstMatch("\"uk\":(\\d+)"),
              let sign = page.firstMatch("\"sign\":\"([a-z0-9]+)\""),
              let timestamp = page.firstMatch("\"timestamp\":(\\d+)"),
              let surl = page.firstMatch("/s/([A-Za-z0-9_-]+)") ?? parsed.shareID else {
            throw ResolveError.failed("百度分享页解析失败（可能需要登录）")
        }

        if let code = parsed.passcode, page.contains("passwd") || page.contains("提取码") {
            let verifyURL = URL(string: "https://pan.baidu.com/share/verify?surl=\(surl)&t=\(Int(Date().timeIntervalSince1970 * 1000))&channel=chunlei&web=1&app_id=250528&clienttype=0")!
            var verifyHeaders = headers
            verifyHeaders["Content-Type"] = "application/x-www-form-urlencoded"
            _ = try? await Http.request(verifyURL, method: "POST", headers: verifyHeaders, body: "pwd=\(code)&vcode=&vcode_str=".data(using: .utf8), userAgent: Http.desktopUA)
        }

        let listURL = URL(string: "https://pan.baidu.com/share/list?uk=\(uk)&shareid=\(shareID)&order=other&desc=1&showempty=0&web=1&page=1&num=100&dir=%2F&t=\(timestamp)&channel=chunlei&app_id=250528&bdstoken=&clienttype=0")!
        let listing = try await Http.json(listURL, headers: headers, userAgent: Http.desktopUA)
        guard let files = dig(listing, ["list"]) as? [Any], !files.isEmpty else {
            throw ResolveError.failed("百度网盘：分享列表为空或需要提取码")
        }

        var items: [MediaItem] = []
        for file in files {
            guard let name = dig(file, ["server_filename"]) as? String else { continue }
            let isDir = (dig(file, ["isdir"]) as? Int) ?? 0
            if isDir == 1 { continue }
            guard let fid = dig(file, ["fs_id"]) else { continue }

            let api = URL(string: "https://pan.baidu.com/api/sharedownload?sign=\(sign)&timestamp=\(timestamp)&channel=chunlei&web=1&app_id=250528&clienttype=0")!
            let form: [String: Any] = ["encrypt": "0", "product": "share", "uk": uk, "primaryid": shareID, "fid_list": "[\(fid)]", "path_list": "[\(name)]"]
            guard let json = try? await Http.json(api, method: "POST", headers: headers, body: form, userAgent: Http.desktopUA),
                  let raw = dig(json, ["dlink"]) as? [Any],
                  let first = raw.first,
                  let rawURL = dig(first, ["dlink"]) as? String,
                  let mediaURL = URL(string: rawURL) else { continue }
            items.append(MediaItem(title: name, url: mediaURL, headers: ["Referer": "https://pan.baidu.com/", "Cookie": cookie, "User-Agent": Http.desktopUA]))
        }

        if items.isEmpty {
            throw ResolveError.failed("百度网盘：没拿到下载地址（需要登录并保持 Cookie，或分享已失效）")
        }
        return ResolveOutput(platform: "百度网盘", title: items.first?.title ?? "百度网盘", items: items, note: "百度限速严格，多线程不一定有用")
    }

    static func lanzou(_ url: URL) async throws -> ResolveOutput {
        let page = try await Http.string(url, headers: ["Referer": url.absoluteString], userAgent: Http.desktopUA)
        let iframe = page.firstMatch("<iframe[^>]+src=\"([^\"]+)\"")
        let target: URL = iframe.flatMap { URL(string: $0, relativeTo: url)?.absoluteURL } ?? url
        let inner: String
        if iframe == nil {
            inner = page
        } else {
            inner = try await Http.string(target, headers: ["Referer": url.absoluteString], userAgent: Http.desktopUA)
        }

        let sign = inner.firstMatch("sign\\s*[:=]\\s*['\"]([a-z0-9]+)['\"]")
        let host = target.host ?? url.host ?? ""

        if let sign = sign, let ajaxURL = URL(string: "https://\(host)/ajaxm.php") {
            var request = URLRequest(url: ajaxURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue(url.absoluteString, forHTTPHeaderField: "Referer")
            request.setValue(Http.desktopUA, forHTTPHeaderField: "User-Agent")
            request.httpBody = "action=downprocess&sign=\(sign)&ves=1".data(using: .utf8)
            if let (data, _) = try? await URLSession.shared.data(for: request),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let domain = json["dom"] as? String, let code = json["url"] as? String,
               let mediaURL = URL(string: "https://\(domain)/file/\(code)") {
                return ResolveOutput(platform: "蓝奏云", title: "蓝奏云文件", items: [MediaItem(title: "蓝奏云文件", url: mediaURL, headers: ["Referer": url.absoluteString])], note: nil)
            }
        }

        if let raw = inner.unescapedJSON.firstMatch("\"?url\"?\\s*[:=]\\s*['\"]([^'\"]+)['\"]"),
           let mediaURL = URL(string: raw, relativeTo: target)?.absoluteURL {
            return ResolveOutput(platform: "蓝奏云", title: "蓝奏云文件", items: [MediaItem(title: mediaURL.lastPathComponent, url: mediaURL, headers: ["Referer": url.absoluteString])], note: nil)
        }
        throw ResolveError.failed("蓝奏云页面没解析出直链（可能需要密码或页面已改版）")
    }

    static func pan123(_ url: URL) async throws -> ResolveOutput {
        guard let shareKey = url.absoluteString.firstMatch("(?:shareKey=|share/)([A-Za-z0-9_-]+)") else {
            throw ResolveError.failed("没认出 123 网盘分享 Key")
        }
        let api = URL(string: "https://www.123pan.com/api/share/info?shareKey=\(shareKey)")!
        let object = try await Http.json(api, headers: ["Referer": "https://www.123pan.com/"])
        let name = (dig(object, ["data", "Info", "FileName"]) as? String) ?? "123网盘"
        throw ResolveError.unsupported("123 网盘要先转存到自己账号才能取直链，暂不支持：\(name)")
    }
}

enum ByteCounter {
    static func string(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: max(0, value))
    }
}
