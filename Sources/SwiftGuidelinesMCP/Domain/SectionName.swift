import Foundation

/// 非空であることが型で保証されたセクション名。
/// 保持する文字列は前後の空白を除去した正規化済みの表示用文字列。
struct SectionName {
    let rawValue: String

    init?(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        rawValue = trimmed
    }
}
