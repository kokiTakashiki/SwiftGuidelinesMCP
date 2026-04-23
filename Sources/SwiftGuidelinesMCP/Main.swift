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

        await registerHandlers(on: server)

        do {
            try await server.start(transport: StdioTransport())
            try await runForever()
        } catch {
            // StdioTransport 使用時は stdout が JSON-RPC に占有されるため、診断出力は stderr に書く。
            let message = "サーバーの起動に失敗しました: \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    }

    /// MCP サーバに公開するツールと、その呼び出しディスパッチを登録する。
    /// ツール追加時はここに一覧を増やし、`GuidelinesToolHandler` に倣って専用ハンドラ型を追加する。
    private static func registerHandlers(on server: Server) async {
        let guidelinesHandler = GuidelinesToolHandler()

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [GuidelinesToolHandler.toolDefinition])
        }

        await server.withMethodHandler(CallTool.self) { params in
            await guidelinesHandler.handle(params: params)
        }
    }

    /// MCP swift-sdk の `Server.start()` はサーバを内部タスクで起動して即座に返るため、
    /// 呼び出し側でプロセス寿命を保持する責務がある。`sleep(1s)` は CPU 負荷を抑えるための
    /// 任意の間隔で、機能的な意味は持たない。
    private static func runForever() async throws {
        while true {
            try await Task.sleep(for: .seconds(1))
        }
    }
}

/// `readSwiftGuidelines` ツールのディスパッチ責務を持つ。
/// ツール定義の保持・引数検証委譲・取得・プレゼンテーション整形までを取りまとめる。
struct GuidelinesToolHandler {
    /// MCP に公開するツール定義。
    /// `inputSchema` は MCP 仕様で JSON Schema 相当が要求されるため、最小構成の `type` と
    /// `properties` のみを持たせている。
    static let toolDefinition = Tool(
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

    let fetcher: GuidelinesFetcher

    init(fetcher: GuidelinesFetcher = GuidelinesFetcher()) {
        self.fetcher = fetcher
    }

    func handle(params: CallTool.Parameters) async -> CallTool.Result {
        guard params.name == GuidelinesToolHandler.toolDefinition.name else {
            return CallTool.Result(
                content: [.text(text: "Tool not found", annotations: nil, _meta: nil)],
                isError: true
            )
        }
        // 引数の検証（空文字列や空白のみの吸収）は `FetchScope.init` に委ねているため、ここでは
        // 生の文字列を渡すだけでよい。
        let scope = FetchScope(requestedSection: params.arguments?["section"]?.stringValue)
        do {
            let body = try await fetcher.fetch(scope: scope)
            let text = GuidelinesResponseFormatter.format(body)
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
/// 保持する文字列は前後の空白を除去した正規化済みの表示用文字列。
struct SectionName {
    let rawValue: String

    init?(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        rawValue = trimmed
    }
}

/// swift.org から Swift API Design Guidelines の HTML を取得し、パーサに橋渡しする責務を持つ。
struct GuidelinesFetcher {
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

/// HTML から Swift API Design Guidelines の本文をプレーンテキストとして抽出する。
/// プレゼンテーション層の責務（ユーザー向けメッセージ整形やローカライズ）は持たない。
struct GuidelinesParser {
    /// セクション検索時に、見出し位置から返す最大行数。
    /// swift.org のガイドラインでは 1 セクション内の本文が概ね数十行に収まるため、
    /// 次見出しへ大きく踏み込まない範囲として 50 行を採用している。
    private static let sectionLineBudget = 50

    /// セクションが見つからなかった場合に、代替として返すプレビュー文字数の上限。
    /// 「何も返さない」より「本文冒頭を見せてユーザーが目視で検索キーワードを調整できる」ほうが
    /// UX 上有用であり、MCP クライアント側の表示が破綻しない程度の量として 500 文字を採用。
    private static let notFoundPreviewCharacterBudget = 500

    /// 指定スコープに応じて、HTML から本文領域を抽出した結果を返す。
    ///
    /// 本文の特定は次の順でフォールバックする（swift.org のテンプレ変更に耐性を持たせるため）:
    /// 1. `<main>` 要素があればその内部のみを対象にする。
    /// 2. なければ `<body>` 要素の内部を対象にする。
    /// 3. いずれも無ければ入力 HTML 全体を対象にする。
    func extract(from html: String, scope: FetchScope) -> ExtractedBody {
        let fullText = plainText(fromHTML: contentRegion(in: html))
        switch scope {
        case .entireDocument:
            return .entireDocument(text: fullText)
        case let .section(name):
            return .section(name: name, result: lookupSection(named: name, in: fullText))
        }
    }

    /// HTML タグ除去と主要な文字実体参照の展開を行い、改行は保持したプレーンテキストを返す。
    /// 行内の連続したスペース・タブのみ 1 つに圧縮する。完全な HTML でもフラグメントでも受け付ける。
    ///
    /// 実体参照の対象は swift.org のガイドライン本文で実際に現れる定番 6 種のみに絞っている
    /// （`&copy;` や `&ndash;` などはテンプレ上出現しないため対象外）。
    /// 新規の参照が混入した場合はここに追記する。
    ///
    /// - Warning: 冪等ではない。既にプレーンテキスト化済みの文字列を渡すと意図せず再変換が走る。
    func plainText(fromHTML htmlFragment: String) -> String {
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
    ///
    /// 探索は次の 2 段階でフォールバックする。どちらも空振りしたら `notFound` を返す。
    /// 1. 見出し行マッチ: swift.org の見出しは基本プレーンテキストなので、行先頭一致で拾えるケースが大半。
    /// 2. 本文中の部分一致: 見出しに記号・注釈・装飾が混じって 1 段目で拾えない場合の保険。
    ///    「とにかく該当語が最初に現れた位置から返す」ことで取りこぼしを減らす。
    func lookupSection(named sectionName: SectionName, in text: String) -> SectionLookupResult {
        let lowerName = sectionName.rawValue.lowercased()
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
            return .found(body: body)
        }

        if let range = text.range(of: sectionName.rawValue, options: .caseInsensitive) {
            let sectionStart = text[range.lowerBound...]
                .components(separatedBy: .newlines)
                .prefix(Self.sectionLineBudget)
                .joined(separator: "\n")
            return .found(body: sectionStart)
        }

        return .notFound(preview: String(text.prefix(Self.notFoundPreviewCharacterBudget)))
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
    case entireDocument(text: String)
    case section(name: SectionName, result: SectionLookupResult)
}

/// セクション検索の結果。
/// - `found`: 抽出できたセクション本文。
/// - `notFound`: 見つからなかった場合のフォールバック用プレビュー。
enum SectionLookupResult {
    case found(body: String)
    case notFound(preview: String)
}

/// MCP クライアントに提示する最終テキストを組み立てるプレゼンテーション層。
/// ここでロケール依存の文面を集約することで、`GuidelinesParser` を純粋な抽出層に保つ。
enum GuidelinesResponseFormatter {
    static func format(_ body: ExtractedBody) -> String {
        switch body {
        case let .entireDocument(text):
            text
        case let .section(name, .found(body)):
            "セクション \"\(name.rawValue)\" に関する内容:\n\n\(body)"
        case let .section(name, .notFound(preview)):
            "セクション \"\(name.rawValue)\" が見つかりませんでした。\n\n利用可能な内容の一部:\n\(preview)"
        }
    }
}

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
