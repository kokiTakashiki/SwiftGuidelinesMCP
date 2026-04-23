import Foundation

/// プレーンテキスト化されたガイドライン本文から、指定セクションを探索する責務を持つ。
struct SectionFinder {
    /// セクション検索時に、見出し位置から返す最大行数。
    /// swift.org のガイドラインでは 1 セクション内の本文が概ね数十行に収まるため、
    /// 次見出しへ大きく踏み込まない範囲として 50 行を採用している。
    private static let sectionLineLimit = 50

    /// セクションが見つからなかった場合に、代替として返すプレビュー文字数の上限。
    /// 「何も返さない」より「本文冒頭を見せてユーザーが目視で検索キーワードを調整できる」ほうが
    /// UX 上有用であり、MCP クライアント側の表示が破綻しない程度の量として 500 文字を採用。
    private static let notFoundPreviewCharacterLimit = 500

    /// プレーンテキストから指定セクションの本文候補を探索する。
    ///
    /// 探索は次の 2 段階でフォールバックする。どちらも空振りしたら `notFound` を返す。
    /// 1. 見出し行マッチ: swift.org の見出しは基本プレーンテキストなので、行先頭一致で拾えるケースが大半。
    /// 2. 本文中の部分一致: 見出しに記号・注釈・装飾が混じって 1 段目で拾えない場合の保険。
    ///    「とにかく該当語が最初に現れた位置から返す」ことで取りこぼしを減らす。
    ///
    /// - Note: 2 段目は真の見出しではなく本文中の単なる言及にヒットする可能性があるが、
    ///   クライアント側が提示結果を見て検索語を調整できる UX 前提で、取りこぼし回避を優先している。
    ///
    /// - Returns: 検索結果（見つかった本文、あるいは冒頭プレビュー）。
    /// - Complexity: O(n)（n は `text.text` の文字数）。
    func find(_ name: SectionName, in text: PlainText) -> SectionLookupResult {
        let lowerName = name.displayText.lowercased()
        let lines = text.text.components(separatedBy: .newlines)

        if let headingIndex = lines.firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            guard trimmed.hasPrefix(lowerName) else { return false }
            let afterPrefix = trimmed.dropFirst(lowerName.count)
            // swift.org の見出しは基本プレーンテキストだが、稀に ":" や ")" が末尾に付くケースが
            // あるため、それらの直後までを見出し一致として許容する。
            return afterPrefix.isEmpty || afterPrefix.first.map { $0.isWhitespace || $0 == ":" || $0 == ")" } ?? false
        }) {
            let body = lines[headingIndex...].prefix(Self.sectionLineLimit).joined(separator: "\n")
            if let sectionBody = SectionBody(body) {
                return .found(sectionBody)
            }
        }

        if let range = text.text.range(of: name.displayText, options: .caseInsensitive) {
            let sectionStart = text.text[range.lowerBound...]
                .components(separatedBy: .newlines)
                .prefix(Self.sectionLineLimit)
                .joined(separator: "\n")
            if let sectionBody = SectionBody(sectionStart) {
                return .found(sectionBody)
            }
        }

        return .notFound(NotFoundPreview(String(text.text.prefix(Self.notFoundPreviewCharacterLimit))))
    }
}
