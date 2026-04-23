/// セクション検索の結果。
/// - `found`: 抽出できたセクション本文。
/// - `notFound`: 見つからなかった場合のフォールバック用プレビュー。
enum SectionLookupResult {
    case found(body: String)
    case notFound(preview: String)
}
