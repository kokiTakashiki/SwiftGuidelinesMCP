import Foundation

/// 非空であることが型で保証されたセクション名。
///
/// 非空保証が必要なのは、空文字列を検索キーにすると行頭一致やプレーンテキスト走査で
/// **すべての行に前方一致** してしまい、最初のセクションが常にヒットする不正動作になるため。
/// failable init で生入力（空白のみ等）を弾き、検索層に空文字列を到達させないことで防いでいる。
struct SectionName: CustomStringConvertible, Equatable {
    let rawValue: String

    /// ラベル `requested:` は「未検証のユーザー入力からの narrowing 変換」という生成経路を
    /// 呼び出し側に明示させる意図。すでに検証済みの値からの構築には使わせない含意がある。
    init?(requested value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        rawValue = trimmed
    }

    var description: String {
        rawValue
    }
}
