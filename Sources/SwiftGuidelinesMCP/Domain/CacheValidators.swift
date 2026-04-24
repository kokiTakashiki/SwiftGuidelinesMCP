/// HTTP 条件付き GET で使う検証子の組。
///
/// `etag` / `lastModified` を `String?` のまま保持しているのは意図的。HTTP-date を
/// `Date` などにパースして再フォーマットすると、サーバ側の表記（タイムゾーン略称・
/// 桁数の揺れ）と一致しなくなり 304 が成立しなくなるリスクがある。「受け取った文字列を
/// そのまま差し戻す」のが条件付き GET の最も安全な実装。
///
/// - Note: かつては `ETag` / `LastModified` を `String` ラップ型として持っていたが、
///   保証する不変条件が無く `rawValue` を素通しする構造だったため、プロパティ名で
///   役割を表現するに留めた（レビューで「型で区別すべき」と指摘されないようここに記録）。
struct CacheValidators: Equatable {
    let etag: String?
    let lastModified: String?

    /// 両方の検証子が不在で、通常の GET と等価に扱える状態。
    var isEmpty: Bool {
        etag == nil && lastModified == nil
    }
}
