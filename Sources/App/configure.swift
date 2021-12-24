import Fluent
import FluentSQLiteDriver
import Leaf
import Vapor
import MQTTNIO

public func configure(_ app: Application) throws {
    
    // HTTP
    
    app.http.server.configuration.requestDecompression = .enabled
    app.http.server.configuration.responseCompression = .enabled
    
    // JSON
    
    ContentConfiguration.global.use(
        decoder: JSONDecoder.custom(dates: .secondsSince1970),
        for: .homeConnectJSONAPI
    )
    ContentConfiguration.global.use(
        encoder: JSONEncoder.custom(dates: .secondsSince1970),
        for: .homeConnectJSONAPI
    )
    
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
    
    // Home Connect
    
    guard let mqttURL = Environment.get("MQTT_URL").flatMap({ URL(string: $0) }) else {
        fatalError("Missing MQTT URL")
    }
    
    let mqttCredentials: MQTTConfiguration.Credentials?
    if let username = Environment.get("MQTT_USERNAME"),
       let password = Environment.get("MQTT_PASSWORD") {
        mqttCredentials = .init(username: username, password: password)
    } else {
        mqttCredentials = nil
    }
    
    app.lifecycle.use(HomeConnectProvider(
        mqttURL: mqttURL,
        mqttCredentials: mqttCredentials
    ))
}
