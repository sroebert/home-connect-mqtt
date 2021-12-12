import Vapor

struct HomeConnectClient {
    var id: String
    var secret: String
    var redirectURL: URI
}

extension Application {
    private struct HomeConnectClientStorageKey: StorageKey {
        typealias Value = HomeConnectClient
    }
    
    var homeConnectClient: HomeConnectClient {
        get {
            guard let client = storage[HomeConnectClientStorageKey.self] else {
                fatalError("HomeConnectClient is not setup")
            }
            return client
        }
        set {
            storage[HomeConnectClientStorageKey.self] = newValue
        }
    }
}
