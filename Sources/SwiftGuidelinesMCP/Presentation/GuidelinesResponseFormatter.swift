/// MCP クライアントに提示する最終テキストを組み立てるプレゼンテーション層。
///
/// この型に文面を集約しているのは、日本語ロケール依存のメッセージが Handler や
/// パース層へ滲み出すのを防ぐため。ローカライズ方針が変わってもここだけを書き換えれば済む。
enum GuidelinesResponseFormatter {
    static func format(_ content: GuidelinesContent) -> PresentedMessage {
        switch content {
        case let .entireDocument(text):
            .success(text.rawValue)
        case let .section(name, .found(body)):
            .success("セクション \"\(name)\" に関する内容:\n\n\(body)")
        case let .section(name, .notFound(preview)):
            .success("セクション \"\(name)\" が見つかりませんでした。\n\n利用可能な内容の一部:\n\(preview)")
        }
    }

    /// エラー文を成功文と同じ窓口に通すことで、ロケール責務がハンドラ側へ漏れ出さないようにしている。
    static func formatError(_ error: Error) -> PresentedMessage {
        .failure("エラー: \(error.localizedDescription)")
    }
}
