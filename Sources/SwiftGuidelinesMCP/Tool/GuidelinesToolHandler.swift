import Foundation
import MCP

/// `readSwiftGuidelines` ツールのディスパッチ責務を持つ。
/// ツール定義の保持・引数検証委譲・取得・プレゼンテーション整形までを取りまとめる。
struct GuidelinesToolHandler: Sendable {
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
