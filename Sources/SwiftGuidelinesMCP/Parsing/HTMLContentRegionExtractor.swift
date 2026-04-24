import Foundation

/// HTML 全体から本文領域だけを切り出す。
///
/// `<main>` → `<body>` → 入力全体 の順でフォールバックしているのは、swift.org のテンプレが
/// 静かに変わってもサーバが落ちないようにするため。本文の特定が崩れた場合でも、最悪
/// 「ページ全体をプレーンテキスト化する」だけに留めて、利用者向けのテキスト提供を継続する。
struct HTMLContentRegionExtractor {
    func contentRegion(in html: RawHTML) -> RawHTML {
        if let extracted = innerHTML(of: "main", in: html.rawValue) {
            return RawHTML(extracted)
        }
        if let extracted = innerHTML(of: "body", in: html.rawValue) {
            return RawHTML(extracted)
        }
        return html
    }

    /// 開始タグ内の属性を読み飛ばすため、開始タグ冒頭から最初の `>` までを境界として破棄してから内側を切り出す。
    private func innerHTML(of tagName: String, in html: String) -> String? {
        guard let openingTag = html.range(of: "<\(tagName)", options: .caseInsensitive) else {
            return nil
        }
        let afterTag = html[openingTag.upperBound...]
        guard let attributesEnd = afterTag.range(of: ">"),
              let closingTag = afterTag.range(of: "</\(tagName)>", options: .caseInsensitive),
              attributesEnd.upperBound <= closingTag.lowerBound
        else {
            return nil
        }
        return String(afterTag[attributesEnd.upperBound ..< closingTag.lowerBound])
    }
}
