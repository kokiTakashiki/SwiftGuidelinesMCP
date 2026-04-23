/// セクション検索の結果。
/// - `found`: 抽出できたセクション本文。
/// - `notFound`: 見つからなかった場合のフォールバック用プレビュー。
///
/// 2 つのケースで意味の異なる文字列を `SectionBody` / `NotFoundPreview` として型で区別し、
/// 後段のプレゼンテーション層が両者を取り違えないよう保証する。
enum SectionLookupResult {
    case found(SectionBody)
    case notFound(NotFoundPreview)
}
