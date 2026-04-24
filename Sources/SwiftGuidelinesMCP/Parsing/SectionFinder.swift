import Foundation

/// プレーンテキスト化されたガイドライン本文から、指定セクションを探索する。
struct SectionFinder {
    /// 1 セクションとして返す最大行数。50 行という値に深い根拠は無く、swift.org の各セクションが
    /// 概ね数十行に収まる経験則。次見出しに踏み込み過ぎず、かつ本文を切り捨て過ぎない閾値として選んだ。
    private static let sectionLineLimit = 50

    /// `notFound` 時にプレビューとして返す上限文字数。「何も返さない」より「冒頭を見せて
    /// 検索キーワード調整の手がかりにしてもらう」ほうが UX 上有用なため設けている。500 字は
    /// MCP クライアント側の表示が破綻しない経験的な上限。
    private static let notFoundPreviewCharacterLimit = 500

    /// 2 段階フォールバックで探す。両方空振りなら `notFound`。
    /// 1. 見出し行マッチ: swift.org の見出しは基本プレーンテキストのため、行頭一致で大半は拾える。
    /// 2. 本文中の部分一致: 見出しに記号や注釈・装飾が混じり 1 段目で拾えない場合の保険。
    ///
    /// 2 段目は **真の見出しではなく本文中の単なる言及にもヒットする** リスクがあるが、提示結果を
    /// 見たクライアント側が検索語を調整できる UX を前提に、取りこぼし回避を優先している。
    ///
    /// - Complexity: O(n)
    func find(_ name: SectionName, in text: PlainText) -> SectionLookupResult {
        let lowerName = name.rawValue.lowercased()
        let plain = text.rawValue
        let lines = plain.components(separatedBy: .newlines)

        if let headingIndex = lines.firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            guard trimmed.hasPrefix(lowerName) else { return false }
            let afterPrefix = trimmed.dropFirst(lowerName.count)
            // 見出しは基本プレーンテキストだが、稀に ":" や ")" が末尾に付く実例があるためそこまで許容する。
            // `?? false` は接尾辞が取れない（見出し名より短い）行を不一致扱いにする保険。
            return afterPrefix.isEmpty || afterPrefix.first.map(Self.isAllowedHeadingSuffix) ?? false
        }) {
            let body = lines[headingIndex...].prefix(Self.sectionLineLimit).joined(separator: "\n")
            if !body.isEmpty {
                return .found(body)
            }
        }

        if let range = plain.range(of: name.rawValue, options: .caseInsensitive) {
            let sectionStart = plain[range.lowerBound...]
                .components(separatedBy: .newlines)
                .prefix(Self.sectionLineLimit)
                .joined(separator: "\n")
            if !sectionStart.isEmpty {
                return .found(sectionStart)
            }
        }

        return .notFound(String(plain.prefix(Self.notFoundPreviewCharacterLimit)))
    }

    private static func isAllowedHeadingSuffix(_ character: Character) -> Bool {
        character.isWhitespace || character == ":" || character == ")"
    }
}
