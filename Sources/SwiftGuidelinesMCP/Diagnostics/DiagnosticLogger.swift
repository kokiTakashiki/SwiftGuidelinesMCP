import Foundation

/// 診断メッセージを外部に通知するための境界型。
///
/// この型を挟んでいるのは、MCP サーバが stdio トランスポートで stdout を JSON-RPC に
/// 占有させているため、`print` などで安易に書くと **プロトコルが壊れる** ため。
/// 「診断は必ず stderr」という制約を呼び出し側が毎回意識せずに済むよう窓口を 1 つに統一し、
/// 出力先（本番の stderr / テスト時のフェイク）は `sink` に閉じ込めている。
///
/// 末尾改行はこの型が付与するため、呼び出し側は改行を含めない文字列を渡す。
struct DiagnosticLogger {
    private let sink: @Sendable (String) -> Void

    init(sink: @escaping @Sendable (String) -> Void) {
        self.sink = sink
    }

    func warn(_ message: String) {
        sink(message)
    }

    static let stderr = DiagnosticLogger { message in
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
