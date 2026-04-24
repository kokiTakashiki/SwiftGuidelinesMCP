import Foundation

/// HTML 断片をタグ除去済みプレーンテキストへ変換する。
///
/// 設計上の割り切り（読み手が驚く可能性が高い箇所）:
/// - 実体参照は swift.org のガイドライン本文に **実出現する 6 種** のみ展開する。`&copy;` などは
///   テンプレ上現れないため対象外にしている。新規参照が混入したらここに追記する。
/// - タグ除去には素朴な正規表現 `<[^>]+>` を使う。属性値の中に裸の `>` を含む HTML は本来正しく
///   扱えないが、対象ドメイン（swift.org の生成 HTML）で発生しないことを前提に簡易実装としている。
///   テンプレが変わって発生し始めたら、HTML パーサへの差し替えが必要。
struct HTMLPlainTextRenderer {
    /// - Complexity: O(n)
    func render(_ html: RawHTML) -> PlainText {
        var text = html.rawValue
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // `&amp;` の置換は **必ず最後に** 行う。先に `&amp;` → `&` に戻すと、`&amp;lt;` のような
        // 多重エスケープが連鎖デコードされて `<` に化けてしまい、原文の意図（`&lt;` という表記
        // そのもの）が失われる。
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
        return PlainText(rendered: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
