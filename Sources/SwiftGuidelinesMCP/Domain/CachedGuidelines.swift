import Foundation

/// キャッシュに保持するレスポンスの immutable スナップショット。
///
/// すべて `let` の値型にしているのは、actor の状態として保持される際に意図しない
/// in-place 書き換えを排除するため。確認時刻の更新は `refreshed(at:)` で新しい
/// スナップショットを生成する形にしている。
struct CachedGuidelines: Equatable {
    let html: RawHTML
    let validators: CacheValidators
    /// 最後に内容が最新と確認できた時刻（200 / 304 受信時）。TTL 判定の起点。
    let fetchedAt: Date

    /// 304 受信時用。本文と検証子は変わらないが、TTL 起点だけは「確認できた」時点に
    /// 進めたいため、この差し替え専用の生成路を用意している。
    func refreshed(at date: Date) -> CachedGuidelines {
        CachedGuidelines(html: html, validators: validators, fetchedAt: date)
    }
}
