import Foundation

/// HTML から Swift API Design Guidelines の本文を抽出するパーサ層のファサード。
/// 3 つの専門責務を合成する薄い窓口であり、プレゼンテーション層の責務
/// （ユーザー向けメッセージ整形やローカライズ）は持たない。
///
/// ## このファサードを残している理由
/// 将来的に取得元（swift.org 以外のキャッシュ・ローカルファイル等）や抽出スコープ
/// （章全体・全セクション一覧・差分取得 等）を増やす際、合成ロジックを 1 箇所に閉じておけば
/// 呼び出し側（ハンドラ・CLI・テスト）の修正が最小化できる。また、テストで 3 コンポーネントを
/// スタブ差し替えする際の窓口としても機能する。
///
/// ## 責務分解
/// - `HTMLContentRegionExtractor`: `<main>` / `<body>` 直下の HTML 断片を取り出す。
/// - `HTMLPlainTextRenderer`: HTML をプレーンテキストに変換する。
/// - `SectionFinder`: プレーンテキストから指定セクションを探索する。
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
