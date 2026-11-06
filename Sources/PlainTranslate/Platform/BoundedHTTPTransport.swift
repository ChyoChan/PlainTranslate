// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import Foundation

/// Bounds decoded response data before buffering it, including chunked or compressed bodies.
final class BoundedHTTPTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maximumBytes: Int
    private let invalidResponse: Error
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var cancelled = false
    private var failure: Error?
    private var response: HTTPURLResponse?
    private var body = Data()

    private init(maximumBytes: Int, invalidResponse: Error) {
        self.maximumBytes = maximumBytes
        self.invalidResponse = invalidResponse
    }

    static func data(for request: URLRequest, configuration: URLSessionConfiguration,
                     maximumBytes: Int, invalidResponse: Error) async throws -> (Data, HTTPURLResponse) {
        let collector = BoundedHTTPTransport(maximumBytes: maximumBytes, invalidResponse: invalidResponse)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                collector.start(request, configuration: configuration, continuation: $0)
            }
        } onCancel: {
            collector.cancel()
        }
    }

    private func start(_ request: URLRequest, configuration: URLSessionConfiguration,
                       continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        lock.unlock()
        task.resume()
    }

    private func cancel() {
        lock.lock()
        cancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let allowed = lock.withLock {
            guard !cancelled, let response = response as? HTTPURLResponse,
                  response.expectedContentLength <= Int64(maximumBytes) else {
                failure = invalidResponse
                return false
            }
            self.response = response
            return true
        }
        completionHandler(allowed ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let allowed = lock.withLock {
            guard !cancelled, failure == nil else { return false }
            guard data.count <= maximumBytes - body.count else {
                failure = invalidResponse
                return false
            }
            body.append(data)
            return true
        }
        if !allowed { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        self.task = nil
        self.session = nil
        let result: Result<(Data, HTTPURLResponse), Error>
        if cancelled { result = .failure(CancellationError()) }
        else if let failure { result = .failure(failure) }
        else if let error { result = .failure(error) }
        else if let response { result = .success((body, response)) }
        else { result = .failure(invalidResponse) }
        lock.unlock()
        session.finishTasksAndInvalidate()
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        lock.withLock { failure = invalidResponse }
        completionHandler(nil)
    }
}
