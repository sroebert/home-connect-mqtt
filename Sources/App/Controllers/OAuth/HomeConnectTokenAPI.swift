import Vapor
import Fluent

struct HomeConnectTokenAPI {
    
    // MARK: - Private Vars
    
    private static let baseURL = "https://api.home-connect.com/security/oauth/"
    
    private static let tokenManager = HomeConnectTokenManager()
    
    private let application: Application
    private let client: Client
    private let db: Database
    
    // MARK: - Lifecycle
    
    init(
        application: Application,
        client: Client,
        database: Database
    ) {
        self.application = application
        self.client = client
        self.db = database
    }
    
    // MARK: - Utils
    
    private func url(forPath path: String) -> URI {
        return URI(string: Self.baseURL + path)
    }
    
    // MARK: - Public
    
    var accessToken: AccessToken {
        get async throws {
            try await Self.tokenManager.getAccessToken {
                try await self.refreshToken()
            }
        }
    }
    
    var authorizationURL: URI {
        get throws {
            var url = url(forPath: "authorize")
            
            let client = application.homeConnectClient
            try ContentConfiguration.global.requireURLEncoder() .encode([
                "client_id": client.id,
                "redirect_uri": client.redirectURL.string,
                "response_type": "code",
                "scope": "IdentifyAppliance Monitor Control Settings"
            ], to: &url)
            
            return url
        }
    }
    
    func processAuthorizationCode(_ code: String) async throws {
        let client = application.homeConnectClient
        try await getToken(for: .authorizationCode(
            code: code,
            redirectUri: client.redirectURL.string,
            clientId: client.id,
            clientSecret: client.secret
        ))
    }
    
    // MARK: - Refresh Token
    
    private func refreshToken() async throws -> AccessToken {
        guard let refreshToken = try await RefreshToken.query(on: db).first() else {
            throw Abort(.unauthorized, reason: "Missing refresh token")
        }
        
        let client = application.homeConnectClient
        return try await getToken(for: .refreshToken(
            refreshToken: refreshToken.refreshToken,
            clientId: client.id,
            clientSecret: client.secret
        ))
    }
    
    @discardableResult
    private func getToken(for content: GrantTokenContent) async throws -> AccessToken {
        let response = try await client.post(url(forPath: "token")) { request in
            try request.content.encode(content, as: .urlEncodedForm)
        }
        
        let token = try response.content.decode(Token.self)
        try await storeRefreshToken(token.refreshToken)
        
        let accessToken = AccessToken(
            token: token.accessToken,
            expires: Date(timeIntervalSinceNow: TimeInterval(token.expiresIn))
        )
        
        await Self.tokenManager.setAccessToken(accessToken)
        
        return accessToken
    }
    
    private func storeRefreshToken(_ refreshToken: String) async throws {
        try await db.transaction { transaction in
            let storedToken = try await RefreshToken.query(on: transaction).first() ?? RefreshToken()
            storedToken.refreshToken = refreshToken
            try await storedToken.save(on: transaction)
        }
    }
}

extension Application {
    var homeConnectTokenAPI: HomeConnectTokenAPI {
        return HomeConnectTokenAPI(
            application: self,
            client: client,
            database: db
        )
    }
}

extension Request {
    var homeConnectTokenAPI: HomeConnectTokenAPI {
        return HomeConnectTokenAPI(
            application: application,
            client: client,
            database: db
        )
    }
}
