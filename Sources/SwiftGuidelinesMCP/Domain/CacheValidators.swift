/// HTTP 条件付き GET で使う検証子の組。
///
/// `ETag` / `LastModified` は本検証子の構成要素としてのみ意味を持つため、
/// `CacheValidators` 内のネスト型として宣言する。これにより use site でも
/// `CacheValidators.ETag(rawValue:)` のように「キャッシュ検証子の ETag」という
/// 意味的スコープが明示される。
struct CacheValidators: Equatable {
    /// HTTP ETag ヘッダ値の型安全ラッパ。`"W/..."` 形式（weak validator）も含めて
    /// サーバから返ってきたそのままを保持し、`If-None-Match` に差し戻すだけの役割を持つ。
    struct ETag: Equatable {
        let rawValue: String
    }

    /// HTTP Last-Modified ヘッダ値の型安全ラッパ。HTTP-date 文字列のまま保持し、
    /// パースはしない（受け取ったまま `If-Modified-Since` に差し戻すことで
    /// フォーマット差異のリスクを避ける）。
    struct LastModified: Equatable {
        let rawValue: String
    }

    let etag: ETag?
    let lastModified: LastModified?

    /// 両方の検証子が不在で、通常の GET と等価に扱える状態。
    var isEmpty: Bool {
        etag == nil && lastModified == nil
    }
}
