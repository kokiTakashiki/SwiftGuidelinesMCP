/// HTML タグ除去・実体参照展開を終えた「プレーンテキスト」を表す型安全ラッパ。
/// `RawHTML` と型レベルで区別することで、プレーンテキスト化済みの文字列に
/// 再度タグ除去を適用してしまう不正な合成をコンパイル時に排除する。
/// 公開プロパティは役割ベースで `text` とする（`value` は中身しか伝えないため避ける）。
struct PlainText {
    let text: String

    init(_ text: String) {
        self.text = text
    }
}
