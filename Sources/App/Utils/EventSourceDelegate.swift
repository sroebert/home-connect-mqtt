import Foundation
import AsyncHTTPClient
import NIOHTTP1
import NIOCore

final class EventSourceDelegate: HTTPClientResponseDelegate {
    
    // MARK: - Types
    
    struct Event {
        var id: String?
        var event: String?
        var data: String?
        var retryTime: Int?
    }
    
    private enum EventField: String {
        case id
        case event
        case data
        case retry
    }
    
    // MARK: - Public Vars
    
    let timeout: TimeAmount?
    let onEvent: (Event) -> Void
    
    // MARK: - Private Vars
    
    private static let newlineDelimiter = "\n".data(using: .utf8)![0]
    private static let crDelimiter = "\r".data(using: .utf8)![0]
    
    private var data: [UInt8] = []
    private var lastByteWasDelimiter = false
    private var lastByteWasCR = false
    private var eventBreaks: [Int] = []
    
    private var timeoutTask: Scheduled<Void>?
    
    // MARK: - Lifecycle
    
    init(timeout: TimeAmount? = nil, onEvent: @escaping (Event) -> Void) {
        self.timeout = timeout
        self.onEvent = onEvent
    }
    
    // MARK: - Events
    
    private func processEvents() {
        var bytesRemoved = 0
        while !eventBreaks.isEmpty {
            let count = eventBreaks.removeFirst() - bytesRemoved
            let eventData = data[0..<count]
            data.removeFirst(count)
            
            bytesRemoved += count
            
            guard
                let eventString = String(data: Data(eventData), encoding: .utf8),
                let event = parseEvent(eventString)
            else {
                continue
            }
            
            onEvent(event)
        }
    }
    
    private func parseEvent(_ eventString: String) -> Event? {
        var parsedData: [EventField: String] = [:]
        
        for line in eventString.components(separatedBy: .newlines) {
            guard let (field, value) = parseEventLine(line) else {
                continue
            }
            
            if let existingValue = parsedData.removeValue(forKey: field) {
                parsedData[field] = existingValue + "\n" + value
            } else {
                parsedData[field] = value
            }
        }
        
        return Event(
            id: parsedData[.id].selfIfNotNilOrEmpty,
            event: parsedData[.event].selfIfNotNilOrEmpty,
            data: parsedData[.data].selfIfNotNilOrEmpty,
            retryTime: parsedData[.retry].selfIfNotNilOrEmpty.flatMap { Int($0) }
        )
    }
    
    private func parseEventLine(_ line: String) -> (field: EventField, value: String)? {
        guard !line.hasPrefix(":") else {
            return nil
        }
        
        let fieldName: String
        let value: String
        if let colonIndex = line.firstIndex(of: ":") {
            fieldName = String(line[line.startIndex..<colonIndex])
            
            let afterColonIndex = line.index(after: colonIndex)
            if afterColonIndex != line.endIndex {
                value = String(line[afterColonIndex...])
            } else {
                value = ""
            }
        } else {
            fieldName = line
            value = ""
        }
        
        guard let field = EventField(rawValue: fieldName) else {
            return nil
        }
        
        return (field, value)
    }
    
    // MARK: - Timeout
    
    private func resetTimeout(for task: HTTPClient.Task<Response>) {
        guard let timeout = timeout else {
            return
        }
        
        timeoutTask?.cancel()
        timeoutTask = task.eventLoop.scheduleTask(in: timeout) {
            task.cancel()
        }
    }
    
    // MARK: - HTTPClientResponseDelegate
    
    typealias Response = Void
    
    func didSendRequestHead(task: HTTPClient.Task<Response>, _ head: HTTPRequestHead) {
        
    }
    
    func didSendRequestPart(task: HTTPClient.Task<Response>, _ part: IOData) {
        
    }
    
    func didSendRequest(task: HTTPClient.Task<Response>) {
        resetTimeout(for: task)
    }
    
    func didReceiveHead(task: HTTPClient.Task<Response>, _ head: HTTPResponseHead) -> EventLoopFuture<Void> {
        guard head.status == .ok else {
            return task.eventLoop.makeFailedFuture(APIError.apiError(head.status))
        }
        
        resetTimeout(for: task)
        return task.eventLoop.makeSucceededFuture(())
    }
    
    func didReceiveBodyPart(task: HTTPClient.Task<Response>, _ buffer: ByteBuffer) -> EventLoopFuture<Void> {
        var buffer = buffer
        while buffer.readableBytes > 0 {
            let byte = buffer.readBytes(length: 1)![0]
            let isDelimiter = (byte == Self.newlineDelimiter || byte == Self.crDelimiter)
            
            if lastByteWasCR && byte == Self.newlineDelimiter {
                lastByteWasCR = false
                continue
            }
            
            if lastByteWasDelimiter && isDelimiter {
                eventBreaks.append(data.count)
            } else {
                data.append(byte)
            }
            
            lastByteWasCR = byte == Self.crDelimiter
            lastByteWasDelimiter = !lastByteWasDelimiter && isDelimiter
        }
        
        processEvents()
        
        resetTimeout(for: task)
        return task.eventLoop.makeSucceededFuture(())
    }
    
    func didReceiveError(task: HTTPClient.Task<Response>, _ error: Error) {
        timeoutTask?.cancel()
    }
    
    func didFinishRequest(task: HTTPClient.Task<Response>) throws -> Response {
        timeoutTask?.cancel()
    }
}
