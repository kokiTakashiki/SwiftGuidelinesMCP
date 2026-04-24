import Foundation

/// キャッシュに保持するレスポンスのスナップショット。
/// 「サーバから 200/304 で確認できた本文＋検証子＋確認時刻」のみを表す純粋な値型。
/// すべて `let` の immutable スナップショットで、確認時刻を更新する際は `refreshed(at:)` で
/// 新しいスナップショットを生成する。
struct CachedGuidelines: Equatable {
    let html: RawHTML
    let validators: CacheValidators
    /// 最後に「内容が最新である」と確認できた時刻（200 受信時 or 304 受信時）。
    /// TTL 判定はこの値を起点に行う。
    let fetchedAt: Date

    /// 304 受信時など、本文と検証子はそのままに確認時刻だけを差し替えた新しいスナップショットを返す。
    func refreshed(at date: Date) -> CachedGuidelines {
        CachedGuidelines(html: html, validators: validators, fetchedAt: date)
    }
}
