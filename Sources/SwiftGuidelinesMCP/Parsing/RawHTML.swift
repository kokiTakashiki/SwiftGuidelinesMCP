/// タグを含む HTML 断片を表す、パース層の型安全ラッパ。
/// 入力がプレーンテキストか HTML かをコンパイル時に区別するため導入している。
/// 公開プロパティは「中身そのもの」を表す汎用語 `value` ではなく、役割ベースで `html` とする。
struct RawHTML {
    let html: String

    init(_ html: String) {
        self.html = html
    }
}
