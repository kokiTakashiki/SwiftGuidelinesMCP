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
