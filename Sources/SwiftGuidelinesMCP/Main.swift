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

        do {
            try await server.start(transport: StdioTransport())
            try await runForever()
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

        await server.withMethodHandler(CallTool.self) { params in
            await guidelinesHandler.handle(params: params)
        }
    }

    /// MCP swift-sdk の `Server.start()` はサーバを内部タスクで起動して即座に返るため、
    /// 呼び出し側でプロセス寿命を保持する責務がある。`sleep(1s)` は CPU 負荷を抑えるための
    /// 任意の間隔で、機能的な意味は持たない。
    private static func runForever() async throws {
        while true {
            try await Task.sleep(for: .seconds(1))
        }
    }
}
