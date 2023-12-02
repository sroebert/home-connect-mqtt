import Vapor
import Fluent
import AsyncHTTPClient

struct HomeConnectAPI {
    
    // MARK: - Private Vars
    
    private static let baseURL = "https://api.home-connect.com/api/"
    
    private let application: Application
    private let tokenAPI: HomeConnectTokenAPI
    private let client: Client
    
    private let limiter = Task {
        await HomeConnectRequestLimiter()
    }
    
    // MARK: - Lifecycle
    
    init(
        application: Application,
        tokenAPI: HomeConnectTokenAPI,
        client: Client
    ) {
        self.application = application
        self.tokenAPI = tokenAPI
        self.client = client
    }
    
    // MARK: - Utils
    
    private func url(forPath path: String) -> URI {
        return URI(string: Self.baseURL + path)
    }
    
    private func request(_ method: HTTPMethod, _ path: String) async throws -> ClientRequest {
        let accessToken = try await tokenAPI.accessToken
        
        let url = url(forPath: path)
        var request = ClientRequest(method: method, url: url, headers: [:], body: nil)
        request.headers.bearerAuthorization = .init(token: accessToken.token)
        
        return request
    }
    
    private func `get`<Result: Content>(_ path: String, at keyPath: CodingKeyRepresentable...) async throws -> Result {
        let request = try await request(.GET, path)
        let response = try await perform(request)
        return try response.content.get(Result.self, at: keyPath)
    }
    
    private func put(_ path: String, data: JSON) async throws {
        var request = try await request(.PUT, path)
        do {
            try request.content.encode(JSON.dictionary([
                "data": data
            ]), as: .homeConnectJSONAPI)
        } catch {
            throw APIError.encodingError(error)
        }
        
        try await perform(request)
    }
    
    @discardableResult
    private func perform(_ request: ClientRequest) async throws -> ClientResponse {
        let response: ClientResponse
        do {
            response = try await limiter.value.perform {
                try await client.send(request)
            }
        } catch {
            throw APIError.connectionError(error)
        }
        
        guard (200..<300).contains(response.status.code) else {
            if response.status == .tooManyRequests,
               let seconds = response.headers.first(name: .retryAfter).flatMap(Int64.init) {
                await limiter.value.disableRequests(for: .seconds(seconds))
            }
            
            if response.status == .unauthorized {
                await tokenAPI.invalidateAccessToken()
            }
            
            throw APIError.apiError(
                response.status,
                response.body.map(String.init)
            )
        }
        
        return response
    }
    
    // MARK: - API
    
    func getAppliances() async throws -> [HomeAppliance] {
        try await get("homeappliances", at: "data", "homeappliances")
    }
    
    func getAppliance(withId applianceId: HomeAppliance.ID) async throws -> HomeAppliance {
        try await get("homeappliances/\(applianceId)", at: "data", "homeappliances")
    }
    
    func getStatus(forApplianceWithId applianceId: HomeAppliance.ID) async throws -> [String: JSON]? {
        try await getKeyValues(forApplianceWithId: applianceId, type: "status")
    }
    
    func getSettings(forApplianceWithId applianceId: HomeAppliance.ID) async throws -> [String: JSON]? {
        try await getKeyValues(forApplianceWithId: applianceId, type: "settings")
    }
    
    private func getKeyValues(forApplianceWithId applianceId: HomeAppliance.ID, type: String) async throws -> [String: JSON]? {
        do {
            let keyValues: [HomeApplianceKeyValue] = try await get(
                "homeappliances/\(applianceId)/\(type)",
                at: "data", type
            )
            return keyValues.parsedDictionary
        } catch APIError.apiError(.conflict, _) {
            return nil
        } catch {
            throw error
        }
    }
    
    func getActiveProgram(forApplianceWithId applianceId: HomeAppliance.ID) async throws -> HomeAppliance.Program? {
        try await getProgram(forApplianceWithId: applianceId, type: "active")
    }
    
    func getSelectedProgram(forApplianceWithId applianceId: HomeAppliance.ID) async throws -> HomeAppliance.Program? {
        try await getProgram(forApplianceWithId: applianceId, type: "selected")
    }
    
    private func getProgram(forApplianceWithId applianceId: HomeAppliance.ID, type: String) async throws -> HomeAppliance.Program? {
        do {
            let programResponse: HomeAppliance.Program.Response = try await get(
                "homeappliances/\(applianceId)/programs/\(type)",
                at: "data"
            )
            return programResponse.parsedProgram
        } catch APIError.apiError(.notFound, _),
                APIError.apiError(.conflict, _) {
            return nil
        } catch {
            throw error
        }
    }
    
    func updateAppliance(withId applianceId: HomeAppliance.ID, path: String, data: JSON) async throws {
        try await put(
            "homeappliances/\(applianceId)/\(path)",
            data: data
        )
    }
    
    // MARK: - Events
    
    private var eventsRequest: HTTPClient.Request {
        get async throws {
            let request = try await request(.GET, "homeappliances/events")
            return try HTTPClient.Request(
                url: URL(string: request.url.string)!,
                method: request.method,
                headers: request.headers,
                body: nil
            )
        }
    }
    
    private func logParsingError(for event: EventSourceDelegate.Event) {
        application.logger.warning("Could not parse received event", metadata: {
            var metadata: Logger.Metadata = [:]
            metadata["id"] = event.id.map { .string($0) }
            metadata["event"] = event.event.map { .string($0) }
            metadata["data"] = event.data.map { .string($0) }
            return metadata
        }())
    }
    
    var events: AsyncThrowingStream<HomeApplianceEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try await eventsRequest
                    
                    let task = application.http.client.shared.execute(
                        request: request,
                        delegate: EventSourceDelegate(timeout: .seconds(70)) { event in
                            guard let homeApplianceEvent = event.homeApplianceEvent else {
                                logParsingError(for: event)
                                return
                            }
                            continuation.yield(homeApplianceEvent)
                        },
                        logger: application.logger
                    )
                    
                    task.futureResult.whenComplete { result in
                        switch result {
                        case .success:
                            continuation.finish()
                            
                        case .failure(let error):
                            guard (error as? HTTPClientError) != .cancelled else {
                                return
                            }
                            continuation.finish(throwing: error)
                        }
                    }
                    
                    continuation.onTermination = { @Sendable _ in
                        task.cancel()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

extension Application {
    var homeConnectAPI: HomeConnectAPI {
        return HomeConnectAPI(
            application: self,
            tokenAPI: homeConnectTokenAPI,
            client: client
        )
    }
}
