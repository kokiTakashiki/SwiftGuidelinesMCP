import Foundation

/// HTML 全体から本文領域（`<main>` / `<body>`）の内側だけを切り出す責務を持つ。
/// swift.org のテンプレ変更に耐性を持たせるため、`main` → `body` → 入力全体 の順でフォールバックする。
struct HTMLContentRegionExtractor {
    /// 入力 HTML から本文領域の HTML 断片を返す。
    /// 本文の特定は次の順でフォールバックする:
    /// 1. `<main>` 要素があればその内部のみを対象にする。
    /// 2. なければ `<body>` 要素の内部を対象にする。
    /// 3. いずれも無ければ入力 HTML 全体を対象にする。
    func contentRegion(in html: RawHTML) -> RawHTML {
        if let extracted = innerHTML(of: "main", in: html.html) {
            return RawHTML(extracted)
        }
        if let extracted = innerHTML(of: "body", in: html.html) {
            return RawHTML(extracted)
        }
        return html
    }

    /// 指定タグ名の開始タグ直後から対応する終了タグ直前までの HTML 断片を返す。
    /// 開始タグ内の属性を読み飛ばすため、開始タグ冒頭から最初の `>` までを境界として破棄する。
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
