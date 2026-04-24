/// セクション検索の結果。
///
/// 中身を `String` にしているのは、かつて `found(SectionBody)` / `notFound(NotFoundPreview)`
/// と専用ラッパ型に分けていたが、enum case 自体が既に「見つかった／見つからなかった」を
/// 判別しているため、型での二重判別になっていた経緯から。`SectionFinder` が `.found` には
/// 非空文字列のみを入れる責務を負うことで、`SectionBody` の非空保証は型ではなく生成元に閉じている。
enum SectionLookupResult: Equatable {
    case found(String)
    /// 見つからなかったときに UX のために提示する本文冒頭のプレビュー。空文字列もありうる。
    case notFound(String)
}
