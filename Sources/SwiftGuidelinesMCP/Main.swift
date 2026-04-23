import Foundation
import MCP

@main
struct SwiftGuidelinesMCP {
    static func main() async {
        let server = Server(
            name: "swift-api-guidelines",
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [Self.readGuidelinesTool])
        }

        await server.withMethodHandler(CallTool.self) { params in
            guard params.name == "readSwiftGuidelines" else {
                return CallTool.Result(
                    content: [.text(text: "Tool not found", annotations: nil, _meta: nil)],
                    isError: true
                )
            }
            let scope = FetchScope(requestedSection: params.arguments?["section"]?.stringValue)
            do {
                let text = try await GuidelinesFetcher().fetch(scope: scope)
                return CallTool.Result(
                    content: [.text(text: text, annotations: nil, _meta: nil)],
                    isError: false
                )
            } catch {
                return CallTool.Result(
                    content: [.text(text: "エラー: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                    isError: true
                )
            }
        }

        do {
            try await server.start(transport: StdioTransport())
            // MCP swift-sdk の Server.start() はサーバを内部タスクで起動して即座に返るため、
            // 呼び出し側でプロセス寿命を保持する責務がある。sleep(1s) は CPU 負荷を抑えるための
            // 任意の間隔で、機能的な意味は持たない。
            while true {
                try await Task.sleep(for: .seconds(1))
            }
        } catch {
            // StdioTransport 使用時は stdout が JSON-RPC に占有されるため、診断出力は stderr に書く。
            let message = "サーバーの起動に失敗しました: \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    }

    private static let readGuidelinesTool = Tool(
        name: "readSwiftGuidelines",
        description: "Swift API Design Guidelinesをswift.orgから読み込みます",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "section": .object([
                    "type": .string("string"),
                    "description": .string("特定のセクション名（例: \"Naming\", \"Clarity\"）。省略した場合、および空文字列や空白のみを指定した場合は全体を返します。"),
                ]),
            ]),
        ])
    )
}

/// ガイドライン取得の対象範囲。
enum FetchScope {
    case entireDocument
    case section(SectionName)

    /// MCP 経由で渡される未検証のセクション指定を安全に解釈する。
    /// `nil` / 空文字列 / 空白のみは `entireDocument` にフォールバックし、
    /// 「空文字列が全行に前方一致する」不正一致を型で排除する。
    init(requestedSection: String?) {
        guard let requestedSection, let name = SectionName(requestedSection) else {
            self = .entireDocument
            return
        }
        self = .section(name)
    }
}

/// 非空であることが型で保証されたセクション名。
struct SectionName {
    let value: String

    init?(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        self.value = trimmed
    }
}

/// swift.org から Swift API Design Guidelines の HTML を取得し、パーサに橋渡しする責務を持つ。
struct GuidelinesFetcher {
    static let defaultURL = URL(string: "https://swift.org/documentation/api-design-guidelines/")!

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

    /// ガイドラインを取得し、指定スコープで本文を抽出したうえで表示用テキストに整形して返す。
    ///
    /// - Parameter scope: 全文取得か特定セクションかを指定する。
    /// - Returns: MCP クライアントにそのまま提示できるプレーンテキスト。
    /// - Throws: レスポンスが HTTP でない、ステータスが 200 以外、UTF-8 デコードに失敗した場合に
    ///           `GuidelinesError` を送出する。
    func fetch(scope: FetchScope) async throws -> String {
        let html = try await fetchHTML()
        let body = parser.extractBody(from: html, scope: scope)
        return GuidelinesResponseFormatter.present(body)
    }

    private func fetchHTML() async throws -> String {
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GuidelinesError.unexpectedResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw GuidelinesError.httpStatus(httpResponse.statusCode)
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw GuidelinesError.invalidEncoding
        }
        return html
    }
}

/// HTML から Swift API Design Guidelines の本文をプレーンテキストとして抽出する。
/// プレゼンテーション層の責務（ユーザー向けメッセージ整形やローカライズ）は持たない。
struct GuidelinesParser {
    /// セクション検索時に、見出し位置から返す最大行数。
    /// swift.org のガイドラインでは 1 セクション内の本文が概ね数十行に収まるため、
    /// 次見出しへ大きく踏み込まない範囲として 50 行を採用している。
    private static let sectionLineBudget = 50

    /// 指定スコープに応じて、HTML から本文領域を抽出した結果を返す。
    ///
    /// 本文の特定は次の順でフォールバックする（swift.org のテンプレ変更に耐性を持たせるため）:
    /// 1. `<main>` 要素があればその内部のみを対象にする。
    /// 2. なければ `<body>` 要素の内部を対象にする。
    /// 3. いずれも無ければ入力 HTML 全体を対象にする。
    func extractBody(from html: String, scope: FetchScope) -> ExtractedBody {
        let fullText = plainText(from: contentRegion(in: html))
        switch scope {
        case .entireDocument:
            return .entireDocument(fullText)
        case let .section(name):
            return .section(name: name, result: lookupSection(named: name, in: fullText))
        }
    }

    /// HTML タグ除去と主要な文字実体参照の展開を行い、改行は保持したプレーンテキストを返す。
    /// 行内の連続したスペース・タブのみ 1 つに圧縮する。完全な HTML でもフラグメントでも受け付ける。
    /// 冪等ではない（すでにプレーンテキスト化済みの文字列を渡すと、実体参照以外の置換は無害だが
    /// 意図せず再変換が走る点に注意）。
    func plainText(from htmlFragment: String) -> String {
        var text = htmlFragment
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// プレーンテキストから、指定セクションの本文候補を探索する。
    func lookupSection(named sectionName: SectionName, in text: String) -> SectionLookupResult {
        let lowerName = sectionName.value.lowercased()
        let lines = text.components(separatedBy: .newlines)

        if let headingIndex = lines.firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            guard trimmed.hasPrefix(lowerName) else { return false }
            let afterPrefix = trimmed.dropFirst(lowerName.count)
            // swift.org の見出しは基本プレーンテキストだが、稀に ":" や ")" が末尾に付くケースが
            // あるため、それらの直後までを見出し一致として許容する。
            return afterPrefix.isEmpty || afterPrefix.first.map { $0.isWhitespace || $0 == ":" || $0 == ")" } ?? false
        }) {
            let body = lines[headingIndex...].prefix(Self.sectionLineBudget).joined(separator: "\n")
            return .found(body)
        }

        if let range = text.range(of: sectionName.value, options: .caseInsensitive) {
            let sectionStart = text[range.lowerBound...]
                .components(separatedBy: .newlines)
                .prefix(Self.sectionLineBudget)
                .joined(separator: "\n")
            return .found(sectionStart)
        }

        return .notFound(preview: String(text.prefix(500)))
    }

    /// 与えられた HTML から本文領域（`<main>` / `<body>`）の内側を抽出する。
    private func contentRegion(in html: String) -> String {
        if let extracted = innerContent(of: "main", in: html) {
            return extracted
        }
        if let extracted = innerContent(of: "body", in: html) {
            return extracted
        }
        return html
    }

    /// 指定タグ名の開始タグ直後から対応する終了タグ直前までを返す。
    /// 開始タグ内の属性を読み飛ばすため、開始タグ冒頭から最初の `>` までを境界として破棄する。
    private func innerContent(of tagName: String, in html: String) -> String? {
        guard let openingTag = html.range(of: "<\(tagName)", options: .caseInsensitive) else {
            return nil
        }
        let afterTag = html[openingTag.upperBound...]
        guard let attributesEnd = afterTag.range(of: ">"),
              let closingTag = afterTag.range(of: "</\(tagName)>", options: .caseInsensitive),
              attributesEnd.upperBound <= closingTag.lowerBound
        else {
            return nil
        }
        return String(afterTag[attributesEnd.upperBound ..< closingTag.lowerBound])
    }
}

/// `GuidelinesParser` が抽出した本文をそのままの形で持ち、プレゼンテーション層に引き渡す中間表現。
enum ExtractedBody {
    case entireDocument(String)
    case section(name: SectionName, result: SectionLookupResult)
}

/// セクション検索の結果。
/// - `found`: 抽出できたセクション本文。
/// - `notFound`: 見つからなかった場合のフォールバック用プレビュー。
enum SectionLookupResult {
    case found(String)
    case notFound(preview: String)
}

/// MCP クライアントに提示する最終テキストを組み立てるプレゼンテーション層。
/// ここでロケール依存の文面を集約することで、`GuidelinesParser` を純粋な抽出層に保つ。
enum GuidelinesResponseFormatter {
    static func present(_ body: ExtractedBody) -> String {
        switch body {
        case let .entireDocument(text):
            text
        case let .section(name, .found(body)):
            "セクション \"\(name.value)\" に関する内容:\n\n\(body)"
        case let .section(name, .notFound(preview)):
            "セクション \"\(name.value)\" が見つかりませんでした。\n\n利用可能な内容の一部:\n\(preview)"
        }
    }
}

/// Swift API Design Guidelines の取得・処理時に発生しうるエラー。
enum GuidelinesError: LocalizedError {
    case unexpectedResponse
    case httpStatus(Int)
    case invalidEncoding

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            "HTTPレスポンスが取得できませんでした"
        case let .httpStatus(code):
            "HTTPリクエストが失敗しました（ステータスコード: \(code)）"
        case .invalidEncoding:
            "エンコーディングエラーが発生しました"
        }
    }
}
