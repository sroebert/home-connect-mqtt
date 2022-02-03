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
    
    private var requestUpdateContinuations: [AsyncStream<Void>.Continuation] = []
    
    private var disableTask: Task<Void, Error>?
    
    // MARK: - Lifecycle
    
    init() async {
        setupRefreshTask()
    }
    
    deinit {
        disableTask?.cancel()
        refreshTask?.cancel()
        requestUpdateContinuations.forEach { $0.finish() }
    }
    
    // MARK: - Utils
    
    private func triggerRequestUpdate() {
        requestUpdateContinuations.forEach { $0.finish() }
        requestUpdateContinuations.removeAll()
    }
    
    private func refreshAllowedRequestCount() {
        allowedRequestCount = Self.requestsPerMinute
        triggerRequestUpdate()
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
            let stream = AsyncStream {
                requestUpdateContinuations.append($0)
            }
            var iterator = stream.makeAsyncIterator()
            await iterator.next()
        }
        
        allowedRequestCount -= 1
        activeRequests += 1
        
        defer {
            activeRequests -= 1
            triggerRequestUpdate()
        }
        
        return try await request()
    }
}
