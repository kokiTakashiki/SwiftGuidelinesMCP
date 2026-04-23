import Foundation

/// HTML から Swift API Design Guidelines の本文をプレーンテキストとして抽出する。
/// プレゼンテーション層の責務（ユーザー向けメッセージ整形やローカライズ）は持たない。
struct GuidelinesParser {
    /// セクション検索時に、見出し位置から返す最大行数。
    /// swift.org のガイドラインでは 1 セクション内の本文が概ね数十行に収まるため、
    /// 次見出しへ大きく踏み込まない範囲として 50 行を採用している。
    private static let sectionLineBudget = 50

    /// セクションが見つからなかった場合に、代替として返すプレビュー文字数の上限。
    /// 「何も返さない」より「本文冒頭を見せてユーザーが目視で検索キーワードを調整できる」ほうが
    /// UX 上有用であり、MCP クライアント側の表示が破綻しない程度の量として 500 文字を採用。
    private static let notFoundPreviewCharacterBudget = 500

    /// 指定スコープに応じて、HTML から本文領域を抽出した結果を返す。
    ///
    /// 本文の特定は次の順でフォールバックする（swift.org のテンプレ変更に耐性を持たせるため）:
    /// 1. `<main>` 要素があればその内部のみを対象にする。
    /// 2. なければ `<body>` 要素の内部を対象にする。
    /// 3. いずれも無ければ入力 HTML 全体を対象にする。
    func extract(from html: String, scope: FetchScope) -> ExtractedBody {
        let fullText = plainText(fromHTML: contentRegion(in: html))
        switch scope {
        case .entireDocument:
            return .entireDocument(text: fullText)
        case let .section(name):
            return .section(name: name, result: lookupSection(named: name, in: fullText))
        }
    }

    /// HTML タグ除去と主要な文字実体参照の展開を行い、改行は保持したプレーンテキストを返す。
    /// 行内の連続したスペース・タブのみ 1 つに圧縮する。完全な HTML でもフラグメントでも受け付ける。
    ///
    /// 実体参照の対象は swift.org のガイドライン本文で実際に現れる定番 6 種のみに絞っている
    /// （`&copy;` や `&ndash;` などはテンプレ上出現しないため対象外）。
    /// 新規の参照が混入した場合はここに追記する。
    ///
    /// - Warning: 冪等ではない。既にプレーンテキスト化済みの文字列を渡すと意図せず再変換が走る。
    func plainText(fromHTML htmlFragment: String) -> String {
        var text = htmlFragment
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// プレーンテキストから、指定セクションの本文候補を探索する。
    ///
    /// 探索は次の 2 段階でフォールバックする。どちらも空振りしたら `notFound` を返す。
    /// 1. 見出し行マッチ: swift.org の見出しは基本プレーンテキストなので、行先頭一致で拾えるケースが大半。
    /// 2. 本文中の部分一致: 見出しに記号・注釈・装飾が混じって 1 段目で拾えない場合の保険。
    ///    「とにかく該当語が最初に現れた位置から返す」ことで取りこぼしを減らす。
    func lookupSection(named sectionName: SectionName, in text: String) -> SectionLookupResult {
        let lowerName = sectionName.rawValue.lowercased()
        let lines = text.components(separatedBy: .newlines)

        if let headingIndex = lines.firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            guard trimmed.hasPrefix(lowerName) else { return false }
            let afterPrefix = trimmed.dropFirst(lowerName.count)
            // swift.org の見出しは基本プレーンテキストだが、稀に ":" や ")" が末尾に付くケースが
            // あるため、それらの直後までを見出し一致として許容する。
            return afterPrefix.isEmpty || afterPrefix.first.map { $0.isWhitespace || $0 == ":" || $0 == ")" } ?? false
        }) {
            let body = lines[headingIndex...].prefix(Self.sectionLineBudget).joined(separator: "\n")
            return .found(body: body)
        }

        if let range = text.range(of: sectionName.rawValue, options: .caseInsensitive) {
            let sectionStart = text[range.lowerBound...]
                .components(separatedBy: .newlines)
                .prefix(Self.sectionLineBudget)
                .joined(separator: "\n")
            return .found(body: sectionStart)
        }

        return .notFound(preview: String(text.prefix(Self.notFoundPreviewCharacterBudget)))
    }

    /// 与えられた HTML から本文領域（`<main>` / `<body>`）の内側を抽出する。
    private func contentRegion(in html: String) -> String {
        if let extracted = innerContent(of: "main", in: html) {
            return extracted
        }
        if let extracted = innerContent(of: "body", in: html) {
            return extracted
        }
        return html
    }

    /// 指定タグ名の開始タグ直後から対応する終了タグ直前までを返す。
    /// 開始タグ内の属性を読み飛ばすため、開始タグ冒頭から最初の `>` までを境界として破棄する。
    private func innerContent(of tagName: String, in html: String) -> String? {
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
