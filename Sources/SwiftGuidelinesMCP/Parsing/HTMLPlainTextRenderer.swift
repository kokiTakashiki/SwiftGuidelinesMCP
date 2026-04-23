import Foundation

/// HTML 断片をタグ除去済みのプレーンテキストへ変換する責務を持つ。
///
/// 実体参照の対象は swift.org のガイドライン本文で実際に現れる定番 6 種のみに絞っている
/// （`&copy;` や `&ndash;` などはテンプレ上出現しないため対象外）。新規の参照が混入した場合はここに追記する。
///
/// タグ除去には素朴な正規表現 `<[^>]+>` を用いている。これは swift.org の生成 HTML が
/// 属性値の中に裸の `>` を含まないテンプレである前提に依存している。属性値内の `>` を含む
/// HTML を正しく扱うためには HTML パーサが必要になるが、対象ドメインの入力では発生しないため
/// 意図的に簡易実装としている。テンプレが変わった際は本正規表現の見直しが必要。
struct HTMLPlainTextRenderer {
    /// タグ除去・主要な文字実体参照の展開を行い、改行は保持したプレーンテキストを返す。
    /// 行内の連続スペース／タブは 1 つに圧縮する。
    ///
    /// 入力を `RawHTML`、出力を `PlainText` として型で区別することで、既に
    /// プレーンテキスト化済みの文字列に再度同じ処理を適用する不正な合成を排除している。
    ///
    /// - Parameter html: タグを含む HTML 断片。完全な HTML でもフラグメントでも受け付ける。
    /// - Returns: タグ除去済みのプレーンテキスト。
    /// - Complexity: O(n)（n は `html.html` の文字数）。
    func render(_ html: RawHTML) -> PlainText {
        var text = html.html
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // `&amp;` の置換は他の参照より後ろに置く必要がある。先に `&amp;` を `&` に戻すと、
        // 例えば `&amp;lt;` のような多重エスケープを連鎖デコードしてしまい、`<` と展開されて
        // 原文の意図（`&lt;` という表記そのもの）が失われる。
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
        return PlainText(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
