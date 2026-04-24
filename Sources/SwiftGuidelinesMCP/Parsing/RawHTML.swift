/// タグを含む HTML 断片の型安全ラッパ。
///
/// 単なる `String` ではなく専用型としているのは、`PlainText`（タグ除去済み）と
/// コンパイル時に区別するため。これがないと、既にタグ除去した文字列に対して再度
/// タグ除去を適用するなどの不正な合成が静かに通ってしまう。
struct RawHTML: Equatable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}
