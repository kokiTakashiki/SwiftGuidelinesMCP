import Foundation

/// HTML から Swift API Design Guidelines の本文を抽出するパーサ層のファサード。
///
/// 3 つの専門責務（領域抽出 / プレーンテキスト化 / セクション探索）を合成する薄い窓口で、
/// プレゼンテーション層の責務（ユーザー向けメッセージ整形やローカライズ）は持たない。
/// 合成箇所を 1 箇所に閉じておくことで、テスト時のスタブ差し替え窓口も兼ねる。
struct GuidelinesParser {
    let regionExtractor: HTMLContentRegionExtractor
    let textRenderer: HTMLPlainTextRenderer
    let sectionFinder: SectionFinder

    init(
        regionExtractor: HTMLContentRegionExtractor = HTMLContentRegionExtractor(),
        textRenderer: HTMLPlainTextRenderer = HTMLPlainTextRenderer(),
        sectionFinder: SectionFinder = SectionFinder()
    ) {
        self.regionExtractor = regionExtractor
        self.textRenderer = textRenderer
        self.sectionFinder = sectionFinder
    }

    /// 指定スコープに応じて、HTML から本文を抽出した中間表現を返す。
    ///
    /// - Parameters:
    ///   - html: パース対象の HTML。swift.org のガイドラインテンプレを想定。
    ///   - scope: 抽出範囲（全体 or 指定セクション）。
    /// - Returns: プレゼンテーション層にそのまま渡せる中間表現。
    func extract(from html: RawHTML, scope: FetchScope) -> GuidelinesContent {
        let fullText = textRenderer.render(regionExtractor.contentRegion(in: html))
        switch scope {
        case .entireDocument:
            return .entireDocument(fullText)
        case let .section(name):
            return .section(name: name, lookup: sectionFinder.find(name, in: fullText))
        }
    }
}
