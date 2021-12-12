import Vapor

struct HomeAppliance: Content {
    
    // MARK: - Public Vars
    
    var id: String
    var name: String
    var brand: String
    var type: String
    
    var isConnected: Bool
    
    // MARK: - Codable
            
    private enum CodingKeys: String, CodingKey {
        case id = "haId"
        case name
        case brand
        case type
        case isConnected = "connected"
    }
}
