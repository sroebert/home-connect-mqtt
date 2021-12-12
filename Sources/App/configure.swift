import Fluent
import FluentSQLiteDriver
import Leaf
import Vapor

public func configure(_ app: Application) throws {
    
    // HTTP
    app.http.server.configuration.requestDecompression = .enabled
    app.http.server.configuration.responseCompression = .enabled
    
    // Database
    
    let dbPath = "\(app.directory.workingDirectory)Data"
    try FileManager.default.createDirectory(atPath: dbPath, withIntermediateDirectories: true)
    app.databases.use(.sqlite(.file("\(dbPath)/db.sqlite")), as: .sqlite)
    
    app.migrations.add(CreateRefreshToken())
    try app.autoMigrate().wait()

    // Views
    
    app.views.use(.leaf)

    // Routes
    
    try routes(app)
    
    // Client
    
    if let id = Environment.get("HOME_CONNECT_CLIENT_ID"),
       let secret = Environment.get("HOME_CONNECT_CLIENT_SECRET"),
       let redirectURL = Environment.get("HOME_CONNECT_REDIRECT_URL") {
        app.homeConnectClient = .init(
            id: id,
            secret: secret,
            redirectURL: URI(string: redirectURL)
        )
    }
}
