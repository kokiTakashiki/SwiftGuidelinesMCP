import Foundation

/// revalidation 時に捕捉した失敗を、actor 境界を越えて保持するための Sendable な値型。
///
/// `any Error` のままでは `Sendable` 制約と両立しないため、捕捉時点で既知の
/// `GuidelinesError` を構造化された case に畳み、その他は `description` に落として保持する。
/// `URLError` などのネットワーク系もここでは `.other` に束ねる。
///
/// 人間向けメッセージは `GuidelinesError.errorDescription` に単一の定義を置き、
/// この型はそこへ委譲するだけにすることで、文面の二重管理を避ける。
enum RevalidationFailure: Equatable {
    case nonHTTPResponse
    case unsuccessfulStatus(code: Int)
    case decodingUTF8Failed
    case unexpectedNotModifiedOnFirstFetch
    case other(description: String)

    init(_ error: any Error) {
        switch error {
        case GuidelinesError.nonHTTPResponse:
            self = .nonHTTPResponse
        case let GuidelinesError.unsuccessfulStatus(code):
            self = .unsuccessfulStatus(code: code)
        case GuidelinesError.decodingUTF8Failed:
            self = .decodingUTF8Failed
        case GuidelinesError.unexpectedNotModifiedOnFirstFetch:
            self = .unexpectedNotModifiedOnFirstFetch
        default:
            self = .other(description: Self.describe(error))
        }
    }

    /// 人間向けの 1 行メッセージ。警告ログや `lastRevalidationFailure` の確認に用いる。
    /// 文面は `GuidelinesError` 側に一元化している。
    var description: String {
        switch self {
        case .nonHTTPResponse:
            GuidelinesError.nonHTTPResponse.localizedDescription
        case let .unsuccessfulStatus(code):
            GuidelinesError.unsuccessfulStatus(code: code).localizedDescription
        case .decodingUTF8Failed:
            GuidelinesError.decodingUTF8Failed.localizedDescription
        case .unexpectedNotModifiedOnFirstFetch:
            GuidelinesError.unexpectedNotModifiedOnFirstFetch.localizedDescription
        case let .other(description):
            description
        }
    }

    private static func describe(_ error: any Error) -> String {
        (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
