import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// swift.org から Swift API Design Guidelines の HTML 文字列を取得する責務のみを持つ。
/// パース・本文抽出・整形には関与しない（責務分離のため、取得結果を `RawHTML` として
/// そのまま返し、合成は `GuidelinesToolHandler` 側で行う）。
struct GuidelinesFetcher {
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

    init(url: URL = GuidelinesFetcher.defaultURL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    /// ガイドラインの HTML を取得する。
    ///
    /// 戻り値の型 `RawHTML` が「HTML である」ことを保証するため、メソッド名からは
    /// 型情報（`HTML`）を省き、副作用のあるイミュータブル動詞 `fetch` を用いている。
    ///
    /// - Returns: ダウンロードした HTML 文字列のラッパ値。
    /// - Throws: レスポンスが HTTP でない、ステータスが 200 以外、UTF-8 デコードに失敗した場合に
    ///           `GuidelinesError` を送出する。
    func fetch() async throws -> RawHTML {
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GuidelinesError.nonHTTPResponse
        }
        // 2xx 全体ではなく 200 のみを成功と認める。ガイドライン本文は 200 でなければ
        // 取得できない前提であり、204 など本文欠落を伴うコードを「成功」として下流に
        // 流すと後段が空テキストで破綻するため、ここで明示的に失敗扱いにする。
        guard httpResponse.statusCode == 200 else {
            throw GuidelinesError.unsuccessfulStatus(code: httpResponse.statusCode)
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw GuidelinesError.decodingUTF8Failed
        }
        return RawHTML(html)
    }
}
