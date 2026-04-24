import Foundation

/// HTML から本文を抽出するパーサ層のファサード。
///
/// 領域抽出 / プレーンテキスト化 / セクション探索の 3 責務を別々の型に分けたうえで、
/// その合成だけをここに集約している。これにより、テストでは構成要素を個別に検証でき、
/// 上位層（Tool ハンドラ）からは「HTML を投げると中間表現が返る」という単一窓口だけを
/// 意識すれば済む。プレゼンテーション層の責務（ローカライズや文面整形）は持たない。
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
