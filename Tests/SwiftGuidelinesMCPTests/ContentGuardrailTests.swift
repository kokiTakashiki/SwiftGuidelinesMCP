import Foundation
import Testing

/// swift.org から取得したコンテンツをリポジトリに同梱しないための保険。
/// HTML ファイルそのものをリポジトリ配下に存在させない運用をテストで固定化する。
@Suite("Content guardrail")
struct ContentGuardrailTests {
    @Test("リポジトリに HTML ファイルが存在しないこと")
    func noHTMLFilesInRepository() throws {
        let repositoryRoot = Self.repositoryRoot()
        let offenders = try Self.findHTMLFiles(under: repositoryRoot)

        #expect(
            offenders.isEmpty,
            """
            リポジトリに HTML ファイルが見つかりました。Swift.org のコンテンツ同梱を避けるため、
            .html / .htm ファイルはリポジトリに含めない運用です。見つかったファイル:
            \(offenders.map { "  - \($0)" }.joined(separator: "\n"))
            """
        )
    }

    /// テストソースの位置からリポジトリルートを導出する。
    /// Tests/SwiftGuidelinesMCPTests/ContentGuardrailTests.swift → 3 階層上がルート。
    private static func repositoryRoot(sourceFile: String = #filePath) -> URL {
        URL(fileURLWithPath: sourceFile)
            .deletingLastPathComponent()  // SwiftGuidelinesMCPTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root
    }

    private static func findHTMLFiles(under root: URL) throws -> [String] {
        let fileManager = FileManager.default
        guard
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]  // .build / .git は隠しディレクトリとして除外される
            )
        else {
            return []
        }

        var offenders: [String] = []
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard ext == "html" || ext == "htm" else { continue }
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            offenders.append(relative)
        }
        return offenders.sorted()
    }
}
