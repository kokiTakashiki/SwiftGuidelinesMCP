/// ガイドライン取得の対象範囲。
enum FetchScope {
    case entireDocument
    case section(SectionName)

    /// MCP 経由で渡される未検証のセクション指定を安全に解釈する。
    /// `nil` / 空文字列 / 空白のみは `entireDocument` にフォールバックし、
    /// 「空文字列が全行に前方一致する」不正一致を型で排除する。
    init(requestedSection: String?) {
        guard let requestedSection, let name = SectionName(requestedSection) else {
            self = .entireDocument
            return
        }
        self = .section(name)
    }
}
