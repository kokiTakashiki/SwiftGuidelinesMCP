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

        // 起動失敗時に retry を **行わない** のは意図的な選択。MCP サーバの再起動は launchd や
        // クライアント側の再接続に委ねる前提で、ここでループするとそれらの正常な再起動戦略を
        // 妨げる可能性があるため。
        do {
            try await server.start(transport: StdioTransport())
            try await keepProcessAlive()
        } catch {
            // stdio トランスポートでは stdout を JSON-RPC が占有しているため、診断は必ず stderr に出す。
            DiagnosticLogger.stderr.warn("サーバーの起動に失敗しました: \(error)")
        }
    }

    private static func registerHandlers(on server: Server) async {
        let fetcher = GuidelinesFetcher()
        let cache = GuidelinesCache(fetcher: fetcher)
        let guidelinesHandler = GuidelinesToolHandler(cache: cache)

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [GuidelinesToolHandler.toolDefinition])
        }

        await server.withMethodHandler(CallTool.self) { parameters in
            await guidelinesHandler.handle(parameters)
        }
    }

    /// MCP swift-sdk の `Server.start()` はサーバを内部 Task で起動して即座に return するため、
    /// 呼び出し側がプロセス寿命を保持する責務を負う。本関数は「何かを動かす」のではなく
    /// 「サーバ Task が走り続けられるようプロセスを生かしておく」だけのために存在する。
    /// `sleep(1s)` の間隔は CPU 負荷を抑える任意値で機能的意味は持たない。
    private static func keepProcessAlive() async throws {
        while true {
            try await Task.sleep(for: .seconds(1))
        }
    }
}
