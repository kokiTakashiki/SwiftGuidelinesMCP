import Foundation

/// ガイドラインの取得・処理時に送出されるエラー。
///
/// `.other` を持たせているのは、revalidation 時に `URLError` などの未分類エラーを捕捉した際に
/// **actor 境界を越えて保持する** 必要があるため。`any Error` のままでは `Sendable` と両立せず
/// `lastRevalidationFailure` のような状態に保存できないので、捕捉時点で `String` に畳んでこの型に
/// 寄せている。`init(_ error:)` がその変換窓口。
enum GuidelinesError: LocalizedError, Equatable {
    case nonHTTPResponse
    case unsuccessfulStatus(code: Int)
    case decodingUTF8Failed
    case unknownTool(name: String)
    case unexpectedNotModifiedOnFirstFetch
    case other(description: String)

    var errorDescription: String? {
        switch self {
        case .nonHTTPResponse:
            "HTTPレスポンスが取得できませんでした"
        case let .unsuccessfulStatus(code):
            "HTTPリクエストが失敗しました（ステータスコード: \(code)）"
        case .decodingUTF8Failed:
            "UTF-8デコードに失敗しました"
        case let .unknownTool(name):
            "未登録のツールが呼び出されました: \(name)"
        case .unexpectedNotModifiedOnFirstFetch:
            "初回取得で 304 が返されました（サーバ仕様違反の可能性があります）"
        case let .other(description):
            description
        }
    }

    /// 任意のエラーをこの型に正規化する。既知ケースはそのまま、それ以外は `.other` に畳む。
    /// 既に `GuidelinesError` のときに二重ラップされないよう先に分岐する。
    init(_ error: any Error) {
        if let known = error as? GuidelinesError {
            self = known
            return
        }
        let description = (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
        self = .other(description: description)
    }
}
