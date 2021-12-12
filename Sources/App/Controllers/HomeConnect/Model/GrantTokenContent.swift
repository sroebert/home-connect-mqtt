import Vapor

enum GrantTokenContent: Content, Validatable {
    case authorizationCode(AuthorizationCodeContent)
    case refreshToken(RefreshTokenContent)
    
    // MARK: - Lifecycle
    
    static func authorizationCode(
        code: String,
        redirectUri: String? = nil,
        clientId: String,
        clientSecret: String
    ) -> Self {
        return .authorizationCode(.init(
            code: code,
            redirectUri: redirectUri,
            clientId: clientId,
            clientSecret: clientSecret
        ))
    }
    
    static func refreshToken(
        refreshToken: String,
        clientId: String,
        clientSecret: String
    ) -> Self {
        return .refreshToken(.init(
            refreshToken: refreshToken,
            clientId: clientId,
            clientSecret: clientSecret
        ))
    }
    
    // MARK: - Validatable
        
    static func validations(_ validations: inout Validations) {
        validations.add(
            "grant_type",
            as: String.self,
            is: .in(AuthorizationCodeContent.grantType, RefreshTokenContent.grantType)
        )
    }
    
    // MARK: - Codable
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let grantType = try container.decode(String.self, forKey: .grantType)
        
        let dataContainer = try decoder.singleValueContainer()
        switch grantType {
        case AuthorizationCodeContent.grantType:
            try AuthorizationCodeContent.validate(decoder)
            self = try .authorizationCode(dataContainer.decode(AuthorizationCodeContent.self))
            
        case RefreshTokenContent.grantType:
            try RefreshTokenContent.validate(decoder)
            self = try .refreshToken(dataContainer.decode(RefreshTokenContent.self))
            
        default:
            throw DecodingError.invalidGrantType
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var dataContainer = encoder.singleValueContainer()
        
        switch self {
        case .authorizationCode(let authorizationCodeContent):
            try dataContainer.encode(authorizationCodeContent)
            
        case .refreshToken(let refreshTokenContent):
            try dataContainer.encode(refreshTokenContent)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
    }
}

extension GrantTokenContent {
    
    // MARK: - Types
    
    enum DecodingError: Error {
        case invalidGrantType
    }
    
    struct AuthorizationCodeContent: Content, Validatable {
        
        // MARK: - Public Vars
        
        static let grantType = "authorization_code"
        
        let grantType = Self.grantType
        var code: String
        var redirectUri: String?
        var clientId: String
        var clientSecret: String
        
        // MARK: - Validatable
        
        static func validations(_ validations: inout Validations) {
            validations.add("redirect_uri", as: String?.self, is: .nil || .url)
        }
        
        // MARK: - Codable
        
        private enum CodingKeys: String, CodingKey {
            case grantType = "grant_type"
            case code
            case clientId = "client_id"
            case clientSecret = "client_secret"
            case redirectUri = "redirect_uri"
        }
    }
    
    struct RefreshTokenContent: Content, Validatable {
        
        // MARK: - Public Vars
        
        static let grantType = "refresh_token"
        
        let grantType = Self.grantType
        var refreshToken: String
        var clientId: String
        var clientSecret: String
        
        // MARK: - Validatable
        
        static func validations(_ validations: inout Validations) {
            
        }
        
        // MARK: - Codable
        
        private enum CodingKeys: String, CodingKey {
            case grantType = "grant_type"
            case refreshToken = "refresh_token"
            case clientId = "client_id"
            case clientSecret = "client_secret"
        }
    }
}
