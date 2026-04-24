import Foundation

/// 非空であることが型で保証されたセクション名。
///
/// 保持する文字列は前後の空白を除去した正規化済みの値で、検索キーと表示の両用途で使う。
/// 他のラッパ（`RawHTML` / `PlainText` など）と揃えてプロパティ名を `rawValue` に統一する。
struct SectionName: CustomStringConvertible, Equatable {
    let rawValue: String

    init?(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        rawValue = trimmed
    }

    var description: String {
        rawValue
    }
}
