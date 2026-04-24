import Foundation

/// 短期 TTL + HTTP 条件付き GET によるキャッシュ層。
/// `GuidelinesToolHandler` と `GuidelinesFetcher` の間に挟まり、
/// 状態（最終取得結果 / 直近のエラー / 進行中リクエスト）を actor として閉じ込める。
///
/// 責務:
/// - TTL 内はキャッシュ即返し（ネットワーク非接続）。
/// - TTL 超過後は検証子付きで再取得し、304 なら fetchedAt を更新、200 なら置換。
/// - 再検証が失敗した場合は可用性優先で stale を返し、警告を `DiagnosticLogger` に委譲。
/// - 同時呼び出しを in-flight Task で 1 本化し、二重 HTTP 発行を防ぐ。
actor GuidelinesCache {
    private let fetcher: any GuidelinesFetching
    private let freshnessWindow: TimeInterval
    private let now: @Sendable () -> Date
    private let logger: DiagnosticLogger
    private var cached: CachedGuidelines?
    /// 直近の revalidation で捕捉した失敗。stale を返した直後のデバッグ確認に用いる。
    /// 成功時は nil にリセットする。
    private(set) var lastRevalidationFailure: RevalidationFailure?
    /// coalescing 用。ネットワーク呼び出しが必要なパスでのみ生成し、
    /// 後続呼び出しは同じ Task を await して二重リクエストを避ける。
    private var inflight: Task<RawHTML, any Error>?

    init(
        fetcher: any GuidelinesFetching,
        freshnessWindow: TimeInterval = 600,
        now: @escaping @Sendable () -> Date = Date.init,
        logger: DiagnosticLogger = .stderr
    ) {
        self.fetcher = fetcher
        self.freshnessWindow = freshnessWindow
        self.now = now
        self.logger = logger
    }

    /// TTL 内であればキャッシュを即返し、超過していれば条件付き GET で再検証する。
    ///
    /// 再検証が失敗した場合は可用性を優先して直前のキャッシュ本文を返す（stale-while-error）。
    /// 同時呼び出しは in-flight Task で 1 本化されるため、ここから HTTP が二重発行されることはない。
    ///
    /// - Returns: キャッシュヒット時はその本文、ミス時は新規取得した本文、再検証失敗時は
    ///   直前に取得した stale な本文。
    /// - Throws: 初回取得が失敗した場合は `fetcher.fetch(using:)` の送出するエラー。
    ///   初回取得で 304 が返った場合は `GuidelinesError.unexpectedNotModifiedOnFirstFetch`。
    func currentGuidelines() async throws -> RawHTML {
        if let inflight {
            return try await inflight.value
        }
        if let cached, now().timeIntervalSince(cached.fetchedAt) < freshnessWindow {
            return cached.html
        }

        let task = Task<RawHTML, any Error> { [self] in
            try await runFetchCycle()
        }
        inflight = task
        // task.value は actor 関数の直後に await されるため、
        // この関数の return 時点で task は完了済み。待機していた別タスクも
        // 既に同じ task.value から結果を受け取っているため、ここで nil に戻しても競合は発生しない。
        defer { inflight = nil }
        return try await task.value
    }

    private func runFetchCycle() async throws -> RawHTML {
        if let cached {
            try await revalidate(previous: cached)
        } else {
            try await performInitialFetch()
        }
    }

    private func performInitialFetch() async throws -> RawHTML {
        let outcome = try await fetcher.fetch(
            using: CacheValidators(etag: nil, lastModified: nil)
        )
        switch outcome {
        case let .fresh(html, validators):
            cached = CachedGuidelines(
                html: html,
                validators: validators,
                fetchedAt: now()
            )
            lastRevalidationFailure = nil
            return html
        case .notModified:
            throw GuidelinesError.unexpectedNotModifiedOnFirstFetch
        }
    }

    private func revalidate(previous: CachedGuidelines) async throws -> RawHTML {
        do {
            let outcome = try await fetcher.fetch(using: previous.validators)
            switch outcome {
            case .notModified:
                let updated = previous.refreshed(at: now())
                cached = updated
                lastRevalidationFailure = nil
                return updated.html
            case let .fresh(html, validators):
                let updated = CachedGuidelines(
                    html: html,
                    validators: validators,
                    fetchedAt: now()
                )
                cached = updated
                lastRevalidationFailure = nil
                return html
            }
        } catch {
            let failure = RevalidationFailure(error)
            lastRevalidationFailure = failure
            logger.warn(Self.warningMessage(fetchedAt: previous.fetchedAt, failure: failure))
            return previous.html
        }
    }

    /// - Important: `revalidation failed` と `fetchedAt=` のリテラルは
    ///   `GuidelinesCacheTests` の部分一致アサートが依存する外部契約。
    ///   変更する場合は対応するテストも合わせて更新する。
    private static func warningMessage(fetchedAt: Date, failure: RevalidationFailure) -> String {
        let timestamp = ISO8601DateFormatter().string(from: fetchedAt)
        return "[SwiftGuidelinesMCP] revalidation failed, returning stale cache (fetchedAt=\(timestamp)): \(failure.description)"
    }
}
