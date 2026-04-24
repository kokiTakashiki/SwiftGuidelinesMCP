/// MCP クライアントに提示する最終テキストを組み立てるプレゼンテーション層。
/// 成功時の整形とエラー時の文言生成を集約することで、日本語ロケール依存の文面を
/// この型に閉じ、`GuidelinesParser` を純粋な抽出層に保つ。
///
/// 戻り値は `PresentedMessage` で成功／失敗の意味をもセットで伝え、ハンドラ側での
/// `isError` フラグとの食い違いを型で排除する。
enum GuidelinesResponseFormatter {
    /// パース済み中間表現をクライアント提示用の成功メッセージに整形する。
    /// - Note: 出力文言は日本語固定。
    static func format(_ content: GuidelinesContent) -> PresentedMessage {
        switch content {
        case let .entireDocument(text):
            .success(text.rawValue)
        case let .section(name, .found(body)):
            .success("セクション \"\(name)\" に関する内容:\n\n\(body.rawValue)")
        case let .section(name, .notFound(preview)):
            .success("セクション \"\(name)\" が見つかりませんでした。\n\n利用可能な内容の一部:\n\(preview.rawValue)")
        }
    }

    /// ハンドラ内で発生したエラーをクライアント提示用の失敗メッセージに整形する。
    /// 成功時の整形と同じ窓口に集約することで、ロケール責務がハンドラ側へ漏れ出さないようにしている。
    static func formatError(_ error: Error) -> PresentedMessage {
        .failure("エラー: \(error.localizedDescription)")
    }
}
