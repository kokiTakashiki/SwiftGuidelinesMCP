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

        // tools/list ハンドラー
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                Tool(
                    name: "readSwiftGuidelines",
                    description: "Swift API Design Guidelinesをswift.orgから読み込みます",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "section": .object([
                                "type": .string("string"),
                                "description": .string("特定のセクション名（例: \"Naming\", \"Clarity\"）。省略時は全体を返します。"),
                            ]),
                        ]),
                    ])
                ),
            ])
        }

        // tools/call ハンドラー
        await server.withMethodHandler(CallTool.self) { params in
            if params.name == "readSwiftGuidelines" {
                do {
                    let section: String? = if let args = params.arguments,
                                              let sectionValue = args["section"]
                    {
                        sectionValue.stringValue
                    } else {
                        nil
                    }

                    let guidelines = try await fetchSwiftGuidelines(section: section)
                    return CallTool.Result(content: [.text(guidelines)], isError: false)
                } catch {
                    return CallTool.Result(
                        content: [.text("エラー: \(error.localizedDescription)")],
                        isError: true
                    )
                }
            }
            return CallTool.Result(content: [.text("Tool not found")], isError: true)
        }

        let transport = StdioTransport()
        do {
            try await server.start(transport: transport)
            // server.start()は非ブロッキングなので、メイン関数が終了しないように無限に待機する
            while true {
                try await Task.sleep(for: .seconds(1))
            }
        } catch {
            print("サーバーの起動に失敗しました: \(error)")
        }
    }

    /// swift.org から Swift API Design Guidelines を取得します。
    ///
    /// - Parameter section: 任意のセクション名（例: "Naming", "Clarity"）。`nil` の場合は全文を返します。
    /// - Returns: ガイドラインのプレーンテキスト。
    /// - Throws: URL不正、ネットワーク失敗、文字コード変換失敗時に `GuidelinesError` を送出します。
    static func fetchSwiftGuidelines(section: String?) async throws -> String {
        let urlString = "https://swift.org/documentation/api-design-guidelines/"
        guard let url = URL(string: urlString) else {
            throw GuidelinesError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw GuidelinesError.networkError("HTTPリクエストが失敗しました")
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw GuidelinesError.encodingError
        }

        return guidelinesText(from: html, section: section)
    }

    /// HTML からガイドライン本文のプレーンテキストを生成し、必要に応じて指定セクションに絞って返します。
    ///
    /// - Parameters:
    ///   - html: 生のHTML文字列（例: `<main>` や `<body>` の内容）。
    ///   - section: 任意のセクション名。`nil` の場合は抽出した全文を返します。
    /// - Returns: HTMLタグ除去とエンティティ展開を行ったプレーンテキスト。
    static func guidelinesText(from html: String, section: String?) -> String {
        // 簡単なHTMLパース: <main>タグまたは記事部分を抽出
        if let mainRange = html.range(of: "<main", options: .caseInsensitive) {
            let afterMain = String(html[mainRange.upperBound...])
            if let mainEndRange = afterMain.range(of: "</main>", options: .caseInsensitive) {
                let mainContent = String(afterMain[..<mainEndRange.lowerBound])
                let text = plainText(from: mainContent)

                if let section {
                    return sectionContent(named: section, from: text)
                }
                return text
            }
        }

        if let bodyRange = html.range(of: "<body", options: .caseInsensitive) {
            let afterBody = String(html[bodyRange.upperBound...])
            if let bodyEndRange = afterBody.range(of: "</body>", options: .caseInsensitive) {
                let bodyContent = String(afterBody[..<bodyEndRange.lowerBound])
                let text = plainText(from: bodyContent)

                if let section {
                    return sectionContent(named: section, from: text)
                }
                return text
            }
        }

        let text = plainText(from: html)
        if let section {
            return sectionContent(named: section, from: text)
        }
        return text
    }

    /// HTMLタグ除去とエンティティ展開を行い、改行を保持したプレーンテキストを返します。
    ///
    /// - Parameter html: 変換対象のHTML文字列。
    /// - Returns: プレーンテキスト。改行は保持し、行内の連続した空白（スペース・タブ）のみを圧縮します。
    static func plainText(from html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        // 改行は保持し、行内の連続スペース・タブのみ単一スペースに
        text = text.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// プレーンテキストから指定セクションの内容を返します。見つからない場合は代替メッセージを返します。
    ///
    /// - Parameters:
    ///   - sectionName: 検索するセクション名（大文字小文字は区別しません）。
    ///   - text: 検索対象のプレーンテキスト。
    /// - Returns: 一致位置から最大50行のセクション本文、またはテキスト先頭を含む代替メッセージ。
    static func sectionContent(named sectionName: String, from text: String) -> String {
        if let range = text.range(of: sectionName, options: .caseInsensitive) {
            let sectionStart = String(text[range.lowerBound...])
            let lines = sectionStart.components(separatedBy: .newlines)
            let relevantLines = Array(lines.prefix(50)).joined(separator: "\n")
            return "セクション \"\(sectionName)\" に関する内容:\n\n\(relevantLines)"
        }
        return "セクション \"\(sectionName)\" が見つかりませんでした。\n\n利用可能な内容の一部:\n\(String(text.prefix(500)))"
    }
}

/// Swift API Design Guidelines の取得・処理時に発生しうるエラー。
enum GuidelinesError: LocalizedError {
    case invalidURL
    case networkError(String)
    case encodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "無効なURLです"
        case let .networkError(message):
            "ネットワークエラー: \(message)"
        case .encodingError:
            "エンコーディングエラーが発生しました"
        }
    }
}
