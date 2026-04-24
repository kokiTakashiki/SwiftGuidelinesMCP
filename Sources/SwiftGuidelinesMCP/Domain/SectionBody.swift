/// セクション検索で抽出できた本文テキスト。非空であることが型で保証される。
/// 「空の本文が `found` として表現される」不整合を排除するため、`SectionName` と同様に
/// failable init で不変条件を守る。
struct SectionBody: Equatable {
    let rawValue: String

    init?(_ rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }
}
