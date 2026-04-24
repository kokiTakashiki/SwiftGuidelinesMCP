/// クライアント提示用テキストを「成功／失敗の意味」とセットで運ぶ型。
///
/// 文字列単独で渡すと、整形側の意図（成功文 / エラー文）と Handler 側の `isError` フラグの
/// 対応付けが手作業になり、「成功なのに `isError: true`」のような取り違え事故を
/// レビューでしか防げなくなる。enum で意味を持たせて型レベルで縛る。
enum PresentedMessage {
    case success(String)
    case failure(String)
}
