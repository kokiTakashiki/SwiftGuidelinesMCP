/// タグ除去・実体参照展開済みのプレーンテキスト。
///
/// `RawHTML` と型レベルで区別しているのは、レンダリング済み文字列に再度タグ除去を
/// 当ててしまう不正な合成（実害として `&amp;` が二重展開される等）をコンパイル時に
/// 排除するため。
struct PlainText: Equatable {
    let rawValue: String

    /// ラベル `rendered:` は「HTML をレンダリングした結果」という生成経路を呼び出し側に
    /// 強制的に明示させ、生の HTML を誤って `PlainText` として包む事故を抑止する。
    init(rendered rawValue: String) {
        self.rawValue = rawValue
    }
}
