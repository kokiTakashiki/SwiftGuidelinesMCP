import Foundation
import Testing
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

@testable import SwiftGuidelinesMCP

/// 共有 URLProtocol ストアを介して `URLSession` にスタブ応答を差し込む。
/// `protocolClasses` 経由で URLSession に登録するため、プロセス全体で静的に状態を共有する。
/// 複数テストが同時に状態を書き換えると混線するため、スイートは `.serialized` で直列実行する。
final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    static let storage = Storage()

    final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var _response: (statusCode: Int, headers: [String: String], body: Data)?
        private var _requests: [URLRequest] = []

        func setResponse(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
            lock.lock(); defer { lock.unlock() }
            _response = (statusCode, headers, body)
        }

        func recordedRequests() -> [URLRequest] {
            lock.lock(); defer { lock.unlock() }
            return _requests
        }

        func reset() {
            lock.lock(); defer { lock.unlock() }
            _response = nil
            _requests = []
        }

        fileprivate func record(_ request: URLRequest) {
            lock.lock(); defer { lock.unlock() }
            _requests.append(request)
        }

        fileprivate func currentResponse() -> (Int, [String: String], Data)? {
            lock.lock(); defer { lock.unlock() }
            return _response
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        URLProtocolStub.storage.record(request)
        guard
            let (code, headers, body) = URLProtocolStub.storage.currentResponse(),
            let url = request.url,
            let response = HTTPURLResponse(
                url: url,
                statusCode: code,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeStubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: configuration)
}

private let stubURL = URL(string: "https://stub.example.test/guidelines")!

@Suite("GuidelinesFetcher", .serialized)
struct GuidelinesFetcherTests {
    init() {
        URLProtocolStub.storage.reset()
    }

    @Test("空の検証子では条件付き GET ヘッダが送信されない")
    func emptyValidatorsSendsNoConditionalHeaders() async throws {
        URLProtocolStub.storage.setResponse(
            statusCode: 200,
            headers: [:],
            body: Data("<html></html>".utf8)
        )
        let fetcher = GuidelinesFetcher(url: stubURL, session: makeStubSession())

        _ = try await fetcher.fetch(using: CacheValidators(etag: nil, lastModified: nil))

        let request = try #require(URLProtocolStub.storage.recordedRequests().first)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == nil)
    }

    @Test("ETag のみ指定すると If-None-Match のみ送信")
    func etagOnlySendsIfNoneMatch() async throws {
        URLProtocolStub.storage.setResponse(
            statusCode: 200,
            headers: [:],
            body: Data("<html></html>".utf8)
        )
        let fetcher = GuidelinesFetcher(url: stubURL, session: makeStubSession())

        _ = try await fetcher.fetch(
            using: CacheValidators(etag: CacheValidators.ETag(rawValue: "\"abc\""), lastModified: nil)
        )

        let request = try #require(URLProtocolStub.storage.recordedRequests().first)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"abc\"")
        #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == nil)
    }

    @Test("Last-Modified のみ指定すると If-Modified-Since のみ送信")
    func lastModifiedOnlySendsIfModifiedSince() async throws {
        URLProtocolStub.storage.setResponse(
            statusCode: 200,
            headers: [:],
            body: Data("<html></html>".utf8)
        )
        let fetcher = GuidelinesFetcher(url: stubURL, session: makeStubSession())

        _ = try await fetcher.fetch(
            using: CacheValidators(etag: nil, lastModified: CacheValidators.LastModified(rawValue: "Wed, 21 Oct 2015 07:28:00 GMT"))
        )

        let request = try #require(URLProtocolStub.storage.recordedRequests().first)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == "Wed, 21 Oct 2015 07:28:00 GMT")
    }

    @Test("両方指定すると両ヘッダが送信される")
    func bothValidatorsSendsBothHeaders() async throws {
        URLProtocolStub.storage.setResponse(
            statusCode: 200,
            headers: [:],
            body: Data("<html></html>".utf8)
        )
        let fetcher = GuidelinesFetcher(url: stubURL, session: makeStubSession())

        _ = try await fetcher.fetch(
            using: CacheValidators(
                etag: CacheValidators.ETag(rawValue: "\"xyz\""),
                lastModified: CacheValidators.LastModified(rawValue: "Wed, 21 Oct 2015 07:28:00 GMT")
            )
        )

        let request = try #require(URLProtocolStub.storage.recordedRequests().first)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"xyz\"")
        #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == "Wed, 21 Oct 2015 07:28:00 GMT")
    }

    @Test("304 応答では .notModified を返し本文を読まない")
    func notModifiedReturnsNotModifiedOutcome() async throws {
        URLProtocolStub.storage.setResponse(
            statusCode: 304,
            headers: [:],
            // 304 でも body フィールドはスタブに積んでおくが、fetcher 側で読まれないことが期待値。
            body: Data("この本文は読まれてはならない".utf8)
        )
        let fetcher = GuidelinesFetcher(url: stubURL, session: makeStubSession())

        let outcome = try await fetcher.fetch(
            using: CacheValidators(etag: CacheValidators.ETag(rawValue: "\"v1\""), lastModified: nil)
        )

        switch outcome {
        case .notModified:
            break
        case .fresh:
            Issue.record(".notModified を期待したが .fresh が返った")
        }
    }

    @Test("200 応答では ETag / Last-Modified が検証子に格納される")
    func freshPopulatesValidatorsFromHeaders() async throws {
        URLProtocolStub.storage.setResponse(
            statusCode: 200,
            headers: [
                "ETag": "\"v2\"",
                "Last-Modified": "Thu, 22 Oct 2015 07:28:00 GMT",
            ],
            body: Data("<html>ok</html>".utf8)
        )
        let fetcher = GuidelinesFetcher(url: stubURL, session: makeStubSession())

        let outcome = try await fetcher.fetch()

        switch outcome {
        case let .fresh(html, validators):
            #expect(html.rawValue == "<html>ok</html>")
            #expect(validators.etag?.rawValue == "\"v2\"")
            #expect(validators.lastModified?.rawValue == "Thu, 22 Oct 2015 07:28:00 GMT")
        case .notModified:
            Issue.record(".fresh を期待したが .notModified が返った")
        }
    }

    @Test("200 応答でヘッダが無ければ検証子は空")
    func freshWithoutHeadersLeavesValidatorsEmpty() async throws {
        URLProtocolStub.storage.setResponse(
            statusCode: 200,
            headers: [:],
            body: Data("<html>body</html>".utf8)
        )
        let fetcher = GuidelinesFetcher(url: stubURL, session: makeStubSession())

        let outcome = try await fetcher.fetch()

        switch outcome {
        case let .fresh(html, validators):
            #expect(html.rawValue == "<html>body</html>")
            #expect(validators.isEmpty)
        case .notModified:
            Issue.record(".fresh を期待したが .notModified が返った")
        }
    }

    @Test("500 応答では unsuccessfulStatus が送出される")
    func serverErrorThrowsUnsuccessfulStatus() async throws {
        URLProtocolStub.storage.setResponse(
            statusCode: 500,
            headers: [:],
            body: Data()
        )
        let fetcher = GuidelinesFetcher(url: stubURL, session: makeStubSession())

        do {
            _ = try await fetcher.fetch()
            Issue.record("throw を期待したが正常終了した")
        } catch let GuidelinesError.unsuccessfulStatus(code) {
            #expect(code == 500)
        } catch {
            Issue.record("想定外のエラー: \(error)")
        }
    }

    @Test("UTF-8 デコード不可の本文では decodingUTF8Failed が送出される")
    func invalidUTF8ThrowsDecodingError() async throws {
        URLProtocolStub.storage.setResponse(
            statusCode: 200,
            headers: [:],
            body: Data([0xFF, 0xFE, 0xFD])
        )
        let fetcher = GuidelinesFetcher(url: stubURL, session: makeStubSession())

        do {
            _ = try await fetcher.fetch()
            Issue.record("throw を期待したが正常終了した")
        } catch GuidelinesError.decodingUTF8Failed {
            // 不正バイト列は `decodingUTF8Failed` に正規化される契約の確認。
        } catch {
            Issue.record("想定外のエラー: \(error)")
        }
    }
}
