import Vapor
import Fluent

struct HomeConnectAPI {
    
    // MARK: - Private Vars
    
    private static let baseURL = "https://api.home-connect.com/api/"
    
    private let application: Application
    private let client: Client
    private let db: Database
    
    // MARK: - Lifecycle
    
    init(application: Application, client: Client, database: Database) {
        self.application = application
        self.client = client
        self.db = database
    }
    
    // MARK: - Utils
    
    private func url(forPath path: String) -> URI {
        return URI(string: Self.baseURL + path)
    }
}

extension Application {
    var homeConnectAPI: HomeConnectAPI {
        return HomeConnectAPI(
            application: self,
            client: client,
            database: db
        )
    }
}

extension Request {
    var homeConnectAPI: HomeConnectAPI {
        return HomeConnectAPI(
            application: application,
            client: client,
            database: db
        )
    }
}
