import Fluent

struct CreateRefreshToken: AsyncMigration {
    func prepare(on database: Database) async throws {
        let token = RefreshToken()
        try await database.schema(RefreshToken.schema)
            .id()
            .field(token.$refreshToken.key, .string, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(RefreshToken.schema).delete()
    }
}
