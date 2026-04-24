import Foundation

/// 診断メッセージを外部に通知するための薄い境界型。
///
/// MCP サーバは stdio プロトコルを stdout で喋るため、診断・警告は必ず stderr に出す
/// 必要がある。呼び出し側がそれを毎回気にしなくて済むよう「warn するだけ」の窓口に統一し、
/// 実体（stderr への書き込み / テスト時のフェイク）は `sink` クロージャに閉じ込める。
///
/// メッセージ末尾の改行はこの型が付与するため、呼び出し側は改行を含めない文字列を渡す。
struct DiagnosticLogger {
    private let sink: @Sendable (String) -> Void

    init(sink: @escaping @Sendable (String) -> Void) {
        self.sink = sink
    }

    /// 警告メッセージを 1 行として外部に通知する。
    /// - Parameter message: 改行を含めないメッセージ本文。
    func warn(_ message: String) {
        sink(message)
    }

    /// 既定の実装。MCP stdio トランスポートと衝突しないよう stderr に改行付きで書き出す。
    static let stderr = DiagnosticLogger { message in
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
