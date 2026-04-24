/// 条件付き GET の結果。304 の場合は本文が無いため `notModified` を分岐として持つ。
enum FetchOutcome {
    case fresh(html: RawHTML, validators: CacheValidators)
    case notModified
}
