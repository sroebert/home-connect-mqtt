import Vapor

struct Token: Content {
    
    // MARK: - Public Vars
    
    var accessToken: String
    var tokenType: String
    var expiresIn: Int
    var refreshToken: String
    var scope: String?
    
    // MARK: - Codable
    
    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}
