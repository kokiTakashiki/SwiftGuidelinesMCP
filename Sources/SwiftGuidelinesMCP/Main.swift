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

        return extractGuidelinesText(from: html, section: section)
    }

    static func extractGuidelinesText(from html: String, section: String?) -> String {
        // 簡単なHTMLパース: <main>タグまたは記事部分を抽出
        // まず、<main>タグの内容を探す
        if let mainRange = html.range(of: "<main", options: .caseInsensitive) {
            let afterMain = String(html[mainRange.upperBound...])
            if let mainEndRange = afterMain.range(of: "</main>", options: .caseInsensitive) {
                let mainContent = String(afterMain[..<mainEndRange.lowerBound])
                let text = stripHTMLTags(from: mainContent)

                if let section {
                    return extractSection(from: text, sectionName: section)
                }
                return text
            }
        }

        // <main>タグが見つからない場合は、<article>や<body>から探す
        if let bodyRange = html.range(of: "<body", options: .caseInsensitive) {
            let afterBody = String(html[bodyRange.upperBound...])
            if let bodyEndRange = afterBody.range(of: "</body>", options: .caseInsensitive) {
                let bodyContent = String(afterBody[..<bodyEndRange.lowerBound])
                let text = stripHTMLTags(from: bodyContent)

                if let section {
                    return extractSection(from: text, sectionName: section)
                }
                return text
            }
        }

        // HTMLタグが見つからない場合は、タグを除去した全文を返す
        let text = stripHTMLTags(from: html)
        if let section {
            return extractSection(from: text, sectionName: section)
        }
        return text
    }

    static func stripHTMLTags(from html: String) -> String {
        var text = html
        // HTMLタグを除去
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // HTMLエンティティをデコード
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        // 複数の空白を1つに
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        // 前後の空白を削除
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractSection(from text: String, sectionName: String) -> String {
        // セクション名で検索（大文字小文字を区別しない）
        let searchPattern = sectionName
        if let range = text.range(of: searchPattern, options: .caseInsensitive) {
            let startIndex = range.lowerBound
            // セクションが見つかった位置から、次の大文字で始まる行または一定の文字数までを返す
            let sectionStart = String(text[startIndex...])
            // 最初の数行を返す（簡易実装）
            let lines = sectionStart.components(separatedBy: .newlines)
            let relevantLines = Array(lines.prefix(50)).joined(separator: "\n")
            return "セクション \"\(sectionName)\" に関する内容:\n\n\(relevantLines)"
        }
        return "セクション \"\(sectionName)\" が見つかりませんでした。\n\n利用可能な内容の一部:\n\(String(text.prefix(500)))"
    }
}

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
