import Foundation
import MCP

/// `readSwiftGuidelines` ツールのディスパッチを担う境界層。
///
/// ここに「取得 → パース → 整形」の合成だけを置き、ドメインのエラーは **境界でのみ**
/// `CallTool.Result` に詰め替える。これによってドメイン側は MCP の表現（`isError` フラグや
/// `CallTool.Result` の構造）を知らずに済み、MCP SDK のバージョンアップで型が変わっても
/// 影響範囲をこのファイルに閉じ込められる。
struct GuidelinesToolHandler {
    /// MCP に公開するツール定義。
    ///
    /// `inputSchema` を辞書リテラルで組んでいるのは、現状 MCP SDK が JSON Schema 相当の
    /// 型安全ビルダ API を提供していないため。型安全な API が出たらそちらに移行する。
    ///
    /// - Note: `section` の説明文は `FetchScope.init(requestedSection:)` と
    ///   `SectionName.init(requested:)` の「空文字列・空白のみは全体を返す」挙動に依存している。
    ///   実装側を変える場合はこの文面も合わせて更新すること。
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

    let cache: GuidelinesCache
    let parser: GuidelinesParser

    init(
        cache: GuidelinesCache = GuidelinesCache(fetcher: GuidelinesFetcher()),
        parser: GuidelinesParser = GuidelinesParser()
    ) {
        self.cache = cache
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

    /// 失敗を `throws` で素直に伝播させ、`CallTool.Result` への詰め替えを `handle(_:)` に集約することで、
    /// ドメインのエラー表現と MCP のエラー表現の対応を 1 箇所だけに保つ。
    private func buildResponse(for parameters: CallTool.Parameters) async throws -> PresentedMessage {
        guard parameters.name == GuidelinesToolHandler.toolDefinition.name else {
            throw GuidelinesError.unknownTool(name: parameters.name)
        }
        // 引数の検証（空文字列・空白の吸収）は `FetchScope.init` 側に任せる契約。
        let scope = FetchScope(requestedSection: parameters.arguments?["section"]?.stringValue)
        let html = try await cache.currentGuidelines()
        let content = parser.extract(from: html, scope: scope)
        return GuidelinesResponseFormatter.format(content)
    }

    /// `success` / `failure` と `isError: false / true` の対応をここに集約することで、
    /// 「成功なのに `isError: true`」のような取り違えを型レベルで起きなくしている。
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
