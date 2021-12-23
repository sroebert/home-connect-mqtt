import Foundation
import NIOCore

actor HomeConnectRequestLimiter {
    
    // MARK: - Private Vars
    
    private static let maxSimultaneousRequests = 20
    private static let requestsPerMinute = 50
    
    private var activeRequests = 0
    private var allowedRequestCount = 0
    private var requestsTemporarilyDisabled = false
    
    private var refreshTask: Task<Void, Never>?
    private var requestUpdateSequence: AsyncStream<Void>!
    private var requestUpdateContinuation: AsyncStream<Void>.Continuation!
    
    private var disableTask: Task<Void, Error>?
    
    // MARK: - Lifecycle
    
    init() async {
        requestUpdateSequence = AsyncStream {
            requestUpdateContinuation = $0
        }
        
        setupRefreshTask()
    }
    
    deinit {
        disableTask?.cancel()
        refreshTask?.cancel()
        requestUpdateContinuation.finish()
    }
    
    // MARK: - Utils
    
    private func refreshAllowedRequestCount() {
        allowedRequestCount = Self.requestsPerMinute
        requestUpdateContinuation.yield()
    }
    
    private func setupRefreshTask() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAllowedRequestCount()
                try? await Task.sleep(for: .minutes(1))
            }
        }
    }
    
    // MARK: - Public
    
    private var canPerformRequest: Bool {
        return !requestsTemporarilyDisabled &&
            allowedRequestCount > 0 &&
            activeRequests + 1 <= Self.maxSimultaneousRequests
    }
    
    func disableRequests(for timeAmount: TimeAmount) {
        requestsTemporarilyDisabled = true
        
        refreshTask?.cancel()
        disableTask?.cancel()
        
        disableTask = Task {
            try await Task.sleep(for: timeAmount)
            
            requestsTemporarilyDisabled = false
            setupRefreshTask()
        }
    }
    
    func perform<Response>(_ request: @Sendable () async throws -> Response) async throws -> Response {
        while !canPerformRequest {
            var iterator = requestUpdateSequence.makeAsyncIterator()
            await iterator.next()
        }
        
        allowedRequestCount -= 1
        activeRequests += 1
        
        defer {
            activeRequests -= 1
            requestUpdateContinuation.yield()
        }
        
        return try await request()
    }
}
