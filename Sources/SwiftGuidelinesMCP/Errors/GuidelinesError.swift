import Foundation

/// Swift API Design Guidelines の取得・処理時に発生しうるエラー。
enum GuidelinesError: LocalizedError {
    case nonHTTPResponse
    case unsuccessfulStatus(code: Int)
    case decodingUTF8Failed

    var errorDescription: String? {
        switch self {
        case .nonHTTPResponse:
            "HTTPレスポンスが取得できませんでした"
        case let .unsuccessfulStatus(code):
            "HTTPリクエストが失敗しました（ステータスコード: \(code)）"
        case .decodingUTF8Failed:
            "UTF-8デコードに失敗しました"
        }
    }
}
