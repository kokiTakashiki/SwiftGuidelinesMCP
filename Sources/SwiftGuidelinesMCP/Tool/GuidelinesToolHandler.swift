import Foundation
import MCP

/// `readSwiftGuidelines` ツールのディスパッチ責務を持つ境界層。
/// 取得 (`GuidelinesFetcher`) → パース (`GuidelinesParser` ファサードへ委譲) → 整形
/// (`GuidelinesResponseFormatter`) の合成を担い、ドメインのエラーは境界でのみ
/// `CallTool.Result` に詰め替える。
struct GuidelinesToolHandler {
    /// MCP に公開するツール定義。
    ///
    /// `inputSchema` は MCP 仕様で JSON Schema 相当が要求されるため、辞書リテラルで
    /// 最小構成（`type` / `properties`）を組み立てている。MCP SDK が型安全な
    /// スキーマビルダ API を提供した場合はそちらへ移行することを想定。
    ///
    /// - Note: `section` の `description` は `FetchScope.init(requestedSection:)` と
    ///   `SectionName.init(_:)` の「空文字列や空白のみは全体を返す」挙動に依存している。
    ///   実装を変える場合はこの文面も揃えること。
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
    let parser: GuidelinesParser

    init(
        fetcher: GuidelinesFetcher = GuidelinesFetcher(),
        parser: GuidelinesParser = GuidelinesParser()
    ) {
        self.fetcher = fetcher
        self.parser = parser
    }

    func handle(_ parameters: CallTool.Parameters) async -> CallTool.Result {
        let message: PresentedMessage
        do {
            message = try await buildResponse(for: parameters)
        } catch {
            message = GuidelinesResponseFormatter.formatError(error)
        }
        return Self.makeResult(from: message)
    }

    /// ツールの本処理。失敗は `throws` でそのまま伝播させ、`CallTool.Result` への詰め替えは
    /// 呼び出し境界層 (`handle(_:)`) に限定する。これによりドメインのエラー表現と MCP
    /// 仕様上のエラー表現を型で分離する。
    private func buildResponse(for parameters: CallTool.Parameters) async throws -> PresentedMessage {
        guard parameters.name == GuidelinesToolHandler.toolDefinition.name else {
            throw GuidelinesError.unknownTool(name: parameters.name)
        }
        // 引数の検証（空文字列や空白のみの吸収）は `FetchScope.init` に委ねているため、ここでは
        // 生の文字列を渡すだけでよい。
        let scope = FetchScope(requestedSection: parameters.arguments?["section"]?.stringValue)
        let html = try await fetcher.fetch()
        let content = parser.extract(from: html, scope: scope)
        return GuidelinesResponseFormatter.format(content)
    }

    /// `PresentedMessage` を MCP の `CallTool.Result` に詰め替える。
    /// 成功／失敗の意味と `isError` フラグの対応を 1 箇所に集約することで、
    /// 「成功なのに `isError: true` を付ける」等の取り違え事故を排除する。
    private static func makeResult(from message: PresentedMessage) -> CallTool.Result {
        switch message {
        case let .success(text):
            CallTool.Result(
                content: [.text(text: text, annotations: nil, _meta: nil)],
                isError: false
            )
        case let .failure(text):
            CallTool.Result(
                content: [.text(text: text, annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }
}
