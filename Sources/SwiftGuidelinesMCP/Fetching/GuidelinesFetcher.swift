import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// 条件付き GET 取得層の抽象。`GuidelinesCache` からは常にこのプロトコル経由でしか
/// 呼ばれないため、テストではネットワークを伴わないスタブに差し替えられる。
protocol GuidelinesFetching: Sendable {
    func fetch(using validators: CacheValidators) async throws -> FetchOutcome
}

/// swift.org から Swift API Design Guidelines の HTML を取得する。
/// パース・本文抽出・整形には関与せず、責務を「条件付き GET の成否を返す」ことに限定している。
struct GuidelinesFetcher: GuidelinesFetching {
    /// リテラルが変わらない限り `URL(string:)` は失敗しないが、万一 nil になった場合は
    /// 不正 URL のままサーバを起動し続けないよう即時クラッシュさせる。これはリリースビルドでも
    /// 効くようあえて `preconditionFailure` を選んでいる（黙って失敗するより即時故障のほうが安全）。
    static let defaultURL: URL = {
        guard let url = URL(string: "https://swift.org/documentation/api-design-guidelines/") else {
            preconditionFailure("Swift API Design Guidelines の既定 URL が不正です")
        }
        return url
    }()

    let url: URL
    let session: URLSession

    init(url: URL = GuidelinesFetcher.defaultURL, session: URLSession? = nil) {
        self.url = url
        self.session = session ?? GuidelinesFetcher.makeSession()
    }

    func fetch(using validators: CacheValidators = CacheValidators(etag: nil, lastModified: nil))
        async throws -> FetchOutcome
    {
        var request = URLRequest(url: url)
        if let etag = validators.etag {
            request.addValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = validators.lastModified {
            request.addValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GuidelinesError.nonHTTPResponse
        }

        switch httpResponse.statusCode {
        case 200:
            guard let html = String(data: data, encoding: .utf8) else {
                throw GuidelinesError.decodingUTF8Failed
            }
            // `allHeaderFields` のキー大小文字ゆれ（"ETag" / "Etag" / "etag"）に巻き込まれないよう、
            // 取得は必ず `value(forHTTPHeaderField:)` 経由にする。
            let responseValidators = CacheValidators(
                etag: httpResponse.value(forHTTPHeaderField: "ETag"),
                lastModified: httpResponse.value(forHTTPHeaderField: "Last-Modified")
            )
            return .fresh(html: RawHTML(html), validators: responseValidators)
        case 304:
            return .notModified
        default:
            throw GuidelinesError.unsuccessfulStatus(code: httpResponse.statusCode)
        }
    }

    /// 専用セッションを構築している理由:
    /// `URLSession.shared` は 304 応答を受けると組み込み `URLCache` がキャッシュ済み 200 応答へ
    /// **透過的に差し替えてしまう**。そのため `statusCode == 304` の分岐が一度も成立せず、
    /// 自前のキャッシュ層（`GuidelinesCache`）が条件付き GET の本来の意味を観測できなくなる。
    /// `URLCache` を無効化し、URLSession 内部キャッシュにも頼らない設定でこれを回避する。
    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }
}
