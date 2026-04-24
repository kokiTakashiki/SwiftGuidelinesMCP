/// ガイドライン取得の対象範囲。
enum FetchScope {
    case entireDocument
    case section(SectionName)

    /// MCP 経由で渡される未検証のセクション指定（文字列）から構築する。
    ///
    /// `nil` / 空文字列 / 空白のみは `entireDocument` にフォールバックする。
    /// これは `SectionName` が空文字列を弾くのと一体の防御で、空のキーワードで全行に
    /// 前方一致する不正な検索動作を型システム側で根絶している。
    init(requestedSection: String?) {
        guard let requestedSection, let name = SectionName(requested: requestedSection) else {
            self = .entireDocument
            return
        }
        self = .section(name)
    }
}
