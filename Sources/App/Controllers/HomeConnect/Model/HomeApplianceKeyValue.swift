import Vapor

struct HomeApplianceKeyValue: Content {
    
    // MARK: - Public Vars
    
    var key: String
    var value: JSON
}

extension Array where Element == HomeApplianceKeyValue {
    var parsedDictionary: [String: JSON] {
        var dictionary: [String: JSON] = [:]
        
        for element in self {
            let parsedKey = element.key.homeConnectKeyValueParsed
            
            let parsedValue: JSON
            switch element.value {
            case .string(let string):
                parsedValue = .string(string.homeConnectKeyValueParsed)
                
            default:
                parsedValue = element.value
            }
            
            dictionary[parsedKey] = parsedValue
        }
        
        return dictionary
    }
}
