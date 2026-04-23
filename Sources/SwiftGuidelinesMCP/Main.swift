import Foundation
import MCP

@main
struct SwiftGuidelinesMCP {
    static func main() async {
        let server = Server(
            name: "swift-api-guidelines",
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )

        await registerHandlers(on: server)

        // 起動が失敗した場合は診断情報を stderr に出してプロセスを終了する方針。
        // 再起動は上位プロセス（launchd / MCP クライアント側の再接続）に委ねる前提のため、
        // ここではリトライを行わない。
        do {
            try await server.start(transport: StdioTransport())
            try await keepProcessAlive()
        } catch {
            // StdioTransport 使用時は stdout が JSON-RPC に占有されるため、診断出力は stderr に書く。
            let message = "サーバーの起動に失敗しました: \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    }

    /// MCP サーバに公開するツールと、その呼び出しディスパッチを登録する。
    /// ツール追加時はここに一覧を増やし、`GuidelinesToolHandler` に倣って専用ハンドラ型を追加する。
    private static func registerHandlers(on server: Server) async {
        let guidelinesHandler = GuidelinesToolHandler()

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [GuidelinesToolHandler.toolDefinition])
        }

        await server.withMethodHandler(CallTool.self) { parameters in
            await guidelinesHandler.handle(parameters)
        }
    }

    /// MCP swift-sdk の `Server.start()` はサーバを内部タスクで起動して即座に返るため、
    /// 呼び出し側でプロセス寿命を保持する責務がある。本関数は「何かを動かす」のではなく
    /// 「サーバが終了するまでプロセスを生かしておく」ためだけに存在する。
    /// `sleep(1s)` は CPU 負荷を抑えるための任意の間隔で、機能的な意味は持たない。
    private static func keepProcessAlive() async throws {
        while true {
            try await Task.sleep(for: .seconds(1))
        }
    }
}
