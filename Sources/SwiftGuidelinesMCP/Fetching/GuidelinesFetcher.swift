import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// 条件付き GET（`If-None-Match` / `If-Modified-Since`）を行い、サーバの応答を
/// `FetchOutcome` で返す取得層の抽象。`GuidelinesCache` からはこのプロトコル経由でのみ
/// 呼ばれるため、テストではスタブに差し替えられる。
protocol GuidelinesFetching: Sendable {
    /// - Parameter validators: 直近取得で得た検証子。空なら通常の GET と同じ挙動。
    /// - Returns: 200 なら `.fresh`、304 なら `.notModified`。
    /// - Throws: HTTP でない／200・304 以外のステータス／UTF-8 デコード失敗時に `GuidelinesError`。
    func fetch(using validators: CacheValidators) async throws -> FetchOutcome
}

/// swift.org から Swift API Design Guidelines の HTML を取得する責務のみを持つ。
/// パース・本文抽出・整形には関与せず、条件付き GET の成否を `FetchOutcome` に詰めて返す。
struct GuidelinesFetcher: GuidelinesFetching {
    /// 既定のガイドライン URL。リテラルが変わらない限り `URL(string:)` は成功し、
    /// 失敗は到達不能なプログラマエラーとして `preconditionFailure` で即時クラッシュさせる
    /// （リリースビルドでもここで止めることで、不正 URL のままサーバを起動し続けるのを防ぐ）。
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

    /// 条件付き GET を試みる。検証子が空の場合は通常の GET と同じ挙動になる。
    ///
    /// - Parameter validators: 直近取得で得た検証子。空なら条件付きヘッダを送らない。
    /// - Returns: 200 なら `.fresh(html:validators:)`、304 なら `.notModified`。
    /// - Throws: HTTP でないレスポンス／200・304 以外のステータス／UTF-8 デコード失敗時に
    ///   対応する `GuidelinesError`。
    func fetch(using validators: CacheValidators = CacheValidators(etag: nil, lastModified: nil))
        async throws -> FetchOutcome
    {
        var request = URLRequest(url: url)
        if let etag = validators.etag {
            request.addValue(etag.rawValue, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = validators.lastModified {
            request.addValue(lastModified.rawValue, forHTTPHeaderField: "If-Modified-Since")
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
            // `allHeaderFields` のキー大小文字ゆれを避けるため、`value(forHTTPHeaderField:)` で取り出す。
            let responseValidators = CacheValidators(
                etag: httpResponse.value(forHTTPHeaderField: "ETag").map(CacheValidators.ETag.init(rawValue:)),
                lastModified: httpResponse.value(forHTTPHeaderField: "Last-Modified").map(CacheValidators.LastModified.init(rawValue:))
            )
            return .fresh(html: RawHTML(html), validators: responseValidators)
        case 304:
            return .notModified
        default:
            throw GuidelinesError.unsuccessfulStatus(code: httpResponse.statusCode)
        }
    }

    /// `URLSession.shared` では 304 応答を受けたときに組み込みの `URLCache` が
    /// キャッシュ済み 200 レスポンスへ透過的に差し替えてしまい、`statusCode == 304` の
    /// 分岐が一度も成立しない。条件付き GET を自前で制御するため、`URLCache` を
    /// 無効化した専用セッションを構築する。
    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }
}
