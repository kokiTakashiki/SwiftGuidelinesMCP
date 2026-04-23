import Foundation

/// 非空であることが型で保証されたセクション名。
/// 保持する文字列は前後の空白を除去した正規化済みの表示用文字列。
struct SectionName: CustomStringConvertible {
    /// クライアントへの表示にそのまま使える正規化済みのセクション名。
    /// `RawRepresentable` には準拠していないため、Swift で慣用の `rawValue` ではなく
    /// 意味に沿った名前として `displayText` を公開している。
    let displayText: String

    init?(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        displayText = trimmed
    }

    var description: String {
        displayText
    }
}
