import Foundation
import Testing

@testable import SwiftGuidelinesMCP

/// テスト時に決定論的に時刻を進められるクロック。
/// `GuidelinesCache` の TTL 判定は `now: () -> Date` 経由で注入されるため、
/// 物理時刻に依存せず TTL 超過を再現できる。
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(start: Date) {
        self.date = start
    }

    var current: Date {
        lock.lock(); defer { lock.unlock() }
        return date
    }

    func advance(by seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        date = date.addingTimeInterval(seconds)
    }
}

/// 呼び出しのたびに渡されたメッセージを配列に溜める警告出力のフェイク。
/// `DiagnosticLogger` の `sink` に差し込んで、キャッシュが stale を返した際の警告行を記録する。
private final class WarningSink: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []

    var diagnosticLogger: DiagnosticLogger {
        DiagnosticLogger { [weak self] message in
            guard let self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            self.messages.append(message)
        }
    }

    var recorded: [String] {
        lock.lock(); defer { lock.unlock() }
        return messages
    }
}

/// `GuidelinesFetching` のスタブ。
/// 応答／エラーを FIFO キューで保持し、`fetch(using:)` は先頭から 1 件取り出して返す。
/// 応答がまだ積まれていなければ `CheckedContinuation` で suspend し、テスト側からの
/// `respond*` 呼び出しで resume される。「fetcher に入った」事実も同様の方式で観測する。
///
/// `AsyncStream` の `makeAsyncIterator().next()` を使うと actor-isolated 格納プロパティに
/// 対する mutating async 呼び出しとして弾かれるため、continuation + キューの形で組む。
private actor StubFetcher: GuidelinesFetching {
    enum StubError: Error, Sendable {
        case simulated(String)
    }

    private enum Pending: Sendable {
        case outcome(FetchOutcome)
        case error(StubError)
    }

    private var pendingResponses: [Pending] = []
    private var responseWaiters: [CheckedContinuation<Pending, Never>] = []
    private var bufferedEnteredCount = 0
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []

    private(set) var receivedValidators: [CacheValidators] = []

    func fetch(using validators: CacheValidators) async throws -> FetchOutcome {
        receivedValidators.append(validators)
        signalEntered()
        let pending = await awaitNextResponse()
        switch pending {
        case let .outcome(outcome):
            return outcome
        case let .error(error):
            throw error
        }
    }

    func respondFresh(html: String, etag: String? = nil, lastModified: String? = nil) {
        enqueue(
            .outcome(
                .fresh(
                    html: RawHTML(html),
                    validators: CacheValidators(
                        etag: etag.map(CacheValidators.ETag.init(rawValue:)),
                        lastModified: lastModified.map(CacheValidators.LastModified.init(rawValue:))
                    )
                )
            )
        )
    }

    func respondNotModified() {
        enqueue(.outcome(.notModified))
    }

    func respondError(_ message: String = "simulated revalidation failure") {
        enqueue(.error(.simulated(message)))
    }

    func waitForFetchEntered() async {
        if bufferedEnteredCount > 0 {
            bufferedEnteredCount -= 1
            return
        }
        await withCheckedContinuation { continuation in
            enteredWaiters.append(continuation)
        }
    }

    private func signalEntered() {
        if enteredWaiters.isEmpty {
            bufferedEnteredCount += 1
        } else {
            let waiter = enteredWaiters.removeFirst()
            waiter.resume()
        }
    }

    private func awaitNextResponse() async -> Pending {
        if !pendingResponses.isEmpty {
            return pendingResponses.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            responseWaiters.append(continuation)
        }
    }

    private func enqueue(_ pending: Pending) {
        if responseWaiters.isEmpty {
            pendingResponses.append(pending)
        } else {
            let waiter = responseWaiters.removeFirst()
            waiter.resume(returning: pending)
        }
    }
}

@Suite("GuidelinesCache")
struct GuidelinesCacheTests {
    @Test("初回呼び出しでは空の検証子で fetcher を 1 回だけ呼ぶ")
    func initialLoadUsesEmptyValidators() async throws {
        let stub = StubFetcher()
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_700_000_000))
        let cache = GuidelinesCache(
            fetcher: stub,
            freshnessWindow: 600,
            now: { clock.current }
        )

        async let result = cache.currentGuidelines()
        await stub.waitForFetchEntered()
        await stub.respondFresh(html: "<html>v1</html>", etag: "\"v1\"")
        let html = try await result

        #expect(html.rawValue == "<html>v1</html>")
        let validators = await stub.receivedValidators
        #expect(validators.count == 1)
        #expect(validators[0].isEmpty)
    }

    @Test("TTL 内の連続呼び出しでは fetcher は追加で呼ばれない")
    func hitsReturnCachedWithoutCallingFetcher() async throws {
        let stub = StubFetcher()
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_700_000_000))
        let cache = GuidelinesCache(
            fetcher: stub,
            freshnessWindow: 600,
            now: { clock.current }
        )

        async let first = cache.currentGuidelines()
        await stub.waitForFetchEntered()
        await stub.respondFresh(html: "<html>v1</html>", etag: "\"v1\"")
        _ = try await first

        // TTL 内で再呼び出し
        clock.advance(by: 60)
        let second = try await cache.currentGuidelines()

        #expect(second.rawValue == "<html>v1</html>")
        let count = await stub.receivedValidators.count
        #expect(count == 1)
    }

    @Test("TTL 超過後は前回の検証子付きで fetcher が呼ばれる")
    func expiryUsesPreviousValidators() async throws {
        let stub = StubFetcher()
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_700_000_000))
        let cache = GuidelinesCache(
            fetcher: stub,
            freshnessWindow: 600,
            now: { clock.current }
        )

        async let first = cache.currentGuidelines()
        await stub.waitForFetchEntered()
        await stub.respondFresh(
            html: "<html>v1</html>",
            etag: "\"v1\"",
            lastModified: "Thu, 22 Oct 2015 07:28:00 GMT"
        )
        _ = try await first

        clock.advance(by: 600)  // TTL 境界ちょうどで revalidate に入る
        async let second = cache.currentGuidelines()
        await stub.waitForFetchEntered()
        await stub.respondNotModified()
        _ = try await second

        let validators = await stub.receivedValidators
        #expect(validators.count == 2)
        #expect(validators[1].etag?.rawValue == "\"v1\"")
        #expect(validators[1].lastModified?.rawValue == "Thu, 22 Oct 2015 07:28:00 GMT")
    }

    @Test("revalidate が 304 なら fetchedAt が更新され再度 TTL 内として扱われる")
    func notModifiedRefreshesFetchedAt() async throws {
        let stub = StubFetcher()
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_700_000_000))
        let cache = GuidelinesCache(
            fetcher: stub,
            freshnessWindow: 600,
            now: { clock.current }
        )

        async let first = cache.currentGuidelines()
        await stub.waitForFetchEntered()
        await stub.respondFresh(html: "<html>v1</html>", etag: "\"v1\"")
        _ = try await first

        clock.advance(by: 700)  // 一度 TTL を突破
        async let second = cache.currentGuidelines()
        await stub.waitForFetchEntered()
        await stub.respondNotModified()
        let secondHTML = try await second
        #expect(secondHTML.rawValue == "<html>v1</html>")

        // fetchedAt が now に再設定されたので、60 秒進めても TTL 内
        clock.advance(by: 60)
        let third = try await cache.currentGuidelines()
        #expect(third.rawValue == "<html>v1</html>")

        let count = await stub.receivedValidators.count
        #expect(count == 2)  // 3 回目は fetcher を呼ばない
    }

    @Test("revalidate が 200 新規取得なら本文と検証子が置換される")
    func freshRevalidationReplacesContent() async throws {
        let stub = StubFetcher()
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_700_000_000))
        let cache = GuidelinesCache(
            fetcher: stub,
            freshnessWindow: 600,
            now: { clock.current }
        )

        async let first = cache.currentGuidelines()
        await stub.waitForFetchEntered()
        await stub.respondFresh(html: "<html>v1</html>", etag: "\"v1\"")
        _ = try await first

        clock.advance(by: 700)
        async let second = cache.currentGuidelines()
        await stub.waitForFetchEntered()
        await stub.respondFresh(html: "<html>v2</html>", etag: "\"v2\"")
        let secondHTML = try await second
        #expect(secondHTML.rawValue == "<html>v2</html>")

        // 次の revalidate では新しい検証子が送られる
        clock.advance(by: 700)
        async let third = cache.currentGuidelines()
        await stub.waitForFetchEntered()
        await stub.respondNotModified()
        _ = try await third

        let validators = await stub.receivedValidators
        #expect(validators.count == 3)
        #expect(validators[2].etag?.rawValue == "\"v2\"")
    }

    @Test("revalidate が throw なら直前の html を返し logger を 1 回呼ぶ")
    func revalidationErrorReturnsStaleAndWarnsOnce() async throws {
        let stub = StubFetcher()
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_700_000_000))
        let sink = WarningSink()
        let cache = GuidelinesCache(
            fetcher: stub,
            freshnessWindow: 600,
            now: { clock.current },
            logger: sink.diagnosticLogger
        )

        async let first = cache.currentGuidelines()
        await stub.waitForFetchEntered()
        await stub.respondFresh(html: "<html>v1</html>", etag: "\"v1\"")
        _ = try await first

        clock.advance(by: 700)
        async let second = cache.currentGuidelines()
        await stub.waitForFetchEntered()
        await stub.respondError("boom")
        let stale = try await second

        #expect(stale.rawValue == "<html>v1</html>")
        #expect(sink.recorded.count == 1)
        #expect(sink.recorded[0].contains("revalidation failed"))
        #expect(sink.recorded[0].contains("fetchedAt="))
    }

    @Test("revalidate が throw なら lastRevalidationFailure にエラーが格納される")
    func revalidationErrorStoresLastFailure() async throws {
        let stub = StubFetcher()
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_700_000_000))
        let cache = GuidelinesCache(
            fetcher: stub,
            freshnessWindow: 600,
            now: { clock.current }
        )

        async let first = cache.currentGuidelines()
        await stub.waitForFetchEntered()
        await stub.respondFresh(html: "<html>v1</html>", etag: "\"v1\"")
        _ = try await first

        clock.advance(by: 700)
        async let second = cache.currentGuidelines()
        await stub.waitForFetchEntered()
        await stub.respondError("boom")
        _ = try await second

        let stored = await cache.lastRevalidationFailure
        #expect(stored != nil)
        #expect(stored?.description.contains("boom") == true)
    }

    @Test("初回取得が throw ならエラーがそのまま伝播する")
    func initialFetchErrorPropagates() async throws {
        let stub = StubFetcher()
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_700_000_000))
        let sink = WarningSink()
        let cache = GuidelinesCache(
            fetcher: stub,
            freshnessWindow: 600,
            now: { clock.current },
            logger: sink.diagnosticLogger
        )

        async let result = cache.currentGuidelines()
        await stub.waitForFetchEntered()
        await stub.respondError("initial failure")

        do {
            _ = try await result
            Issue.record("throw を期待したが成功した")
        } catch is StubFetcher.StubError {
            // 初回失敗はドメインに伝播する契約の確認。
        } catch {
            Issue.record("想定外のエラー: \(error)")
        }
        // stale を返していないため logger も呼ばれていないことを確認
        #expect(sink.recorded.isEmpty)
    }

    @Test("初回取得が .notModified ならサーバ仕様違反として throw する")
    func initialNotModifiedThrowsSpecificError() async throws {
        let stub = StubFetcher()
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_700_000_000))
        let cache = GuidelinesCache(
            fetcher: stub,
            freshnessWindow: 600,
            now: { clock.current }
        )

        async let result = cache.currentGuidelines()
        await stub.waitForFetchEntered()
        await stub.respondNotModified()

        do {
            _ = try await result
            Issue.record("throw を期待したが成功した")
        } catch GuidelinesError.unexpectedNotModifiedOnFirstFetch {
            // 初回の 304 はサーバ仕様違反としてドメインエラーに畳まれる契約の確認。
        } catch {
            Issue.record("想定外のエラー: \(error)")
        }
    }

    @Test("TTL 切れ状態での並行呼び出しは fetcher 呼び出し 1 回に集約される")
    func concurrentCallsAreCoalesced() async throws {
        let stub = StubFetcher()
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_700_000_000))
        let cache = GuidelinesCache(
            fetcher: stub,
            freshnessWindow: 600,
            now: { clock.current }
        )

        // A: 初回呼び出しを先に発火し、fetcher.fetch に入ったことを確認
        let taskA = Task { try await cache.currentGuidelines() }
        await stub.waitForFetchEntered()

        // B: 並行呼び出し。actor に進入し、inflight != nil を観測する機会を与える
        let taskB = Task { try await cache.currentGuidelines() }
        await Task.yield()

        await stub.respondFresh(html: "<html>v1</html>", etag: "\"v1\"")

        let aHTML = try await taskA.value
        let bHTML = try await taskB.value

        #expect(aHTML.rawValue == "<html>v1</html>")
        #expect(bHTML.rawValue == "<html>v1</html>")
        let count = await stub.receivedValidators.count
        #expect(count == 1)
    }

    @Test("coalescing 完了後に TTL 切れで再度呼べば fetcher も再度呼ばれる")
    func inflightIsClearedAfterCompletion() async throws {
        let stub = StubFetcher()
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_700_000_000))
        let cache = GuidelinesCache(
            fetcher: stub,
            freshnessWindow: 600,
            now: { clock.current }
        )

        // 1 回目の並行呼び出し
        let taskA = Task { try await cache.currentGuidelines() }
        await stub.waitForFetchEntered()
        let taskB = Task { try await cache.currentGuidelines() }
        await Task.yield()
        await stub.respondFresh(html: "<html>v1</html>", etag: "\"v1\"")
        _ = try await taskA.value
        _ = try await taskB.value

        // TTL 超過後に再呼び出し
        clock.advance(by: 700)
        async let third = cache.currentGuidelines()
        await stub.waitForFetchEntered()
        await stub.respondNotModified()
        _ = try await third

        let count = await stub.receivedValidators.count
        #expect(count == 2)  // 1 回目（並行）+ 2 回目（TTL 切れ）
    }
}
