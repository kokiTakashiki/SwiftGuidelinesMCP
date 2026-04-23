import Foundation

/// Swift API Design Guidelines の取得・処理時に `GuidelinesFetcher` および
/// `GuidelinesToolHandler` が送出し得るエラー。
enum GuidelinesError: LocalizedError {
    case nonHTTPResponse
    case unsuccessfulStatus(code: Int)
    case decodingUTF8Failed
    case unknownTool(name: String)

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
        }
    }
}
