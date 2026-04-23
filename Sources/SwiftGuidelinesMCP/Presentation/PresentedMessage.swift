/// プレゼンテーション層が生成した「クライアント提示用テキスト」を、成功・失敗の意味とセットで
/// 表現する型。`String` 一本で表現すると、成功文と失敗文を取り違えても型で止められないため、
/// ラッパを導入して `isError` フラグとの食い違いを排除する。
enum PresentedMessage {
    case success(String)
    case failure(String)
}
