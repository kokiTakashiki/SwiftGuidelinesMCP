import Foundation

/// 短期 TTL + HTTP 条件付き GET によるキャッシュ層。
///
/// この層をわざわざ挟んでいる理由:
/// - swift.org のガイドラインは滅多に更新されないため、毎回 HTTP リクエストするのは
///   レイテンシ・帯域・先方サーバ負荷のいずれの面でも無駄が大きい。
/// - 一方で「永続キャッシュ」にすると更新を取り逃がす。`If-None-Match` / `If-Modified-Since`
///   を使えば、変更が無いときはサーバ側で 304 で済むため、ほぼ無料で鮮度を担保できる。
/// - actor として状態（最終取得値・直近のエラー・進行中リクエスト）を一括で閉じ込めることで、
///   複数同時呼び出しから守られる。
///
/// 振る舞いの方針:
/// - TTL 内はキャッシュ即返し（ネットワーク非接続）。
/// - TTL 超過後は検証子付きで再取得し、304 なら fetchedAt のみ更新、200 なら本文ごと置換。
/// - 再検証失敗時は **可用性優先** で stale を返し、警告だけ `DiagnosticLogger` に流す。
///   これは「数分前のガイドラインを返す」より「エラーで何も返せない」ほうが MCP クライアント
///   利用体験を悪化させると判断したため。
/// - 同時呼び出しは in-flight Task で 1 本化し、TTL 失効直後の同時アクセスでも HTTP は二重発行されない。
actor GuidelinesCache {
    private let fetcher: any GuidelinesFetching
    private let freshnessWindow: TimeInterval
    private let now: @Sendable () -> Date
    private let logger: DiagnosticLogger
    private var cached: CachedGuidelines?
    /// 直近の revalidation 失敗。stale を返した直後のデバッグ確認用。成功時は nil にリセットする。
    private(set) var lastRevalidationFailure: GuidelinesError?
    /// in-flight Task。後続呼び出しは同じ Task を await して二重リクエストを避ける。
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
        // ここで nil 戻しても競合しない理由: actor 関数なので `task.value` を直後に await している間、
        // 他の呼び出しは同じ `inflight` を読み取って同じ Task を await している。`defer` 実行時には
        // すべての待機者が結果を受け取り終わっているため、次の呼び出しが nil の inflight を見ても
        // 安全に新しい Task を立ち上げられる。
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
            cached = CachedGuidelines(html: html, validators: validators, fetchedAt: now())
            lastRevalidationFailure = nil
            return html
        case .notModified:
            // 検証子なしの初回 GET に対する 304 は HTTP 仕様違反。サーバ実装の不具合を疑うべき
            // 状況なので明示的にエラーにし、stale を持っていない以上ここで諦める。
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
                let updated = CachedGuidelines(html: html, validators: validators, fetchedAt: now())
                cached = updated
                lastRevalidationFailure = nil
                return html
            }
        } catch {
            // stale-while-error: ここで rethrow せずに stale を返すのが意図的な選択（型解説は冒頭参照）。
            let failure = GuidelinesError(error)
            lastRevalidationFailure = failure
            logger.warn(Self.warningMessage(fetchedAt: previous.fetchedAt, failure: failure))
            return previous.html
        }
    }

    /// - Important: `revalidation failed` と `fetchedAt=` のリテラルは
    ///   `GuidelinesCacheTests` の部分一致アサートが依存する **外部契約**。文面を変える際は
    ///   テストも合わせて更新すること。
    private static func warningMessage(fetchedAt: Date, failure: GuidelinesError) -> String {
        let timestamp = ISO8601DateFormatter().string(from: fetchedAt)
        return "[SwiftGuidelinesMCP] revalidation failed, returning stale cache (fetchedAt=\(timestamp)): \(failure.localizedDescription)"
    }
}
