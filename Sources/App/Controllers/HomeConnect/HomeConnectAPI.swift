import Vapor
import Fluent

struct HomeConnectAPI {
    
    // MARK: - Private Vars
    
    private static let baseURL = "https://api.home-connect.com/api/"
    
    private let tokenAPI: HomeConnectTokenAPI
    private let client: Client
    private let db: Database
    
    // MARK: - Lifecycle
    
    init(
        tokenAPI: HomeConnectTokenAPI,
        client: Client,
        database: Database
    ) {
        self.tokenAPI = tokenAPI
        self.client = client
        self.db = database
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
    
    // MARK: - API
    
    func getAppliances() async throws -> [HomeAppliance] {
        let request = try await request(.GET, "homeappliances")
        let response = try await client.send(request)
        return try response.content.get([HomeAppliance].self, at: "data", "homeappliances")
    }
    
    func getAppliance(withId applianceId: String) async throws -> HomeAppliance {
        let request = try await request(.GET, "homeappliances/\(applianceId)")
        let response = try await client.send(request)
        return try response.content.get(HomeAppliance.self, at: "data")
    }
    
    func getStatus(forApplianceWithId applianceId: String) async throws -> [String: JSON] {
        let request = try await request(.GET, "homeappliances/\(applianceId)/status")
        let response = try await client.send(request)
        
        let statusKeyValues = try response.content.get([HomeApplianceKeyValue].self, at: "data", "status")
        return statusKeyValues.parsedDictionary
    }
    
    func getSettings(forApplianceWithId applianceId: String) async throws -> [String: JSON] {
        let request = try await request(.GET, "homeappliances/\(applianceId)/settings")
        let response = try await client.send(request)
        
        let settingsKeyValues = try response.content.get([HomeApplianceKeyValue].self, at: "data", "settings")
        return settingsKeyValues.parsedDictionary
    }
}

extension Application {
    var homeConnectAPI: HomeConnectAPI {
        return HomeConnectAPI(
            tokenAPI: homeConnectTokenAPI,
            client: client,
            database: db
        )
    }
}
