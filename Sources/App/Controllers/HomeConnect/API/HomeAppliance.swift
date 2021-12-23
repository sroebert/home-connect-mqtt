import Vapor

struct HomeAppliance: Content, Identifiable {
    
    // MARK: - Public Vars
    
    var id: String
    var name: String
    var brand: String
    var type: String
    
    var vib: String
    var eNumber: String
    
    var isConnected: Bool
    
    // MARK: - Codable
            
    private enum CodingKeys: String, CodingKey {
        case id = "haId"
        case name
        case brand
        case type
        case vib
        case eNumber = "enumber"
        case isConnected = "connected"
    }
}
