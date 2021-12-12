import Fluent
import Vapor

final class RefreshToken: Model, Content {
    
    // MARK: - Schema
    
    static let schema = "token"
    
    // MARK: - Public Vars
    
    @ID(key: .id)
    var id: UUID?

    @Field(key: "refresh_token")
    var refreshToken: String
    
    // MARK: - Lifecycle

    init() { }

    init(id: UUID? = nil, refreshToken: String) {
        self.id = id
        self.refreshToken = refreshToken
    }
}
