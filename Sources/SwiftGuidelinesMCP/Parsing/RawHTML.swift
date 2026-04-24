/// タグを含む HTML 断片を表す、パース層の型安全ラッパ。
/// 入力がプレーンテキストか HTML かをコンパイル時に区別するため導入している。
struct RawHTML: Equatable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}
