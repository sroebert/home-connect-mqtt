import Fluent
import Vapor

func routes(_ app: Application) throws {
    app.get { _ in
        HTTPStatus.noContent
    }

    try app.grouped("home-connect")
        .register(collection: OAuthController())
}
