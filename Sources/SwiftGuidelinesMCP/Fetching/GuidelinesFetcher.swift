import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// swift.org から Swift API Design Guidelines の HTML を取得し、パーサに橋渡しする責務を持つ。
struct GuidelinesFetcher: Sendable {
    static let defaultURL: URL = {
        guard let url = URL(string: "https://swift.org/documentation/api-design-guidelines/") else {
            preconditionFailure("Swift API Design Guidelines の既定 URL が不正です")
        }
        return url
    }()

    let url: URL
    let session: URLSession
    let parser: GuidelinesParser

    init(
        url: URL = GuidelinesFetcher.defaultURL,
        session: URLSession = .shared,
        parser: GuidelinesParser = GuidelinesParser()
    ) {
        self.url = url
        self.session = session
        self.parser = parser
    }

    /// ガイドラインを取得し、指定スコープで本文を抽出した中間表現を返す。
    /// プレゼンテーション整形は呼び出し側の責務とする。
    ///
    /// - Parameter scope: 全文取得か特定セクションかを指定する。
    /// - Returns: パース済みの本文中間表現 `ExtractedBody`。
    /// - Throws: レスポンスが HTTP でない、ステータスが 200 以外、UTF-8 デコードに失敗した場合に
    ///           `GuidelinesError` を送出する。
    func fetch(scope: FetchScope) async throws -> ExtractedBody {
        let html = try await downloadHTML()
        return parser.extract(from: html, scope: scope)
    }

    private func downloadHTML() async throws -> String {
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GuidelinesError.nonHTTPResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw GuidelinesError.unsuccessfulStatus(code: httpResponse.statusCode)
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw GuidelinesError.decodingUTF8Failed
        }
        return html
    }
}
