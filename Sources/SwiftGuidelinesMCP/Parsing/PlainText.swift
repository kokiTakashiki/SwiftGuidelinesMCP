/// HTML タグ除去・実体参照展開を終えた「プレーンテキスト」を表す型安全ラッパ。
/// `RawHTML` と型レベルで区別することで、プレーンテキスト化済みの文字列に
/// 再度タグ除去を適用してしまう不正な合成をコンパイル時に排除する。
///
/// イニシャライザの引数ラベル `rendered:` は「HTML をレンダリング済みの結果」という
/// 生成経路を呼び出し箇所に明示させるためのもので、誤って生の HTML を `PlainText`
/// として包んでしまう事故を抑止する。
struct PlainText: Equatable {
    let rawValue: String

    init(rendered rawValue: String) {
        self.rawValue = rawValue
    }
}
