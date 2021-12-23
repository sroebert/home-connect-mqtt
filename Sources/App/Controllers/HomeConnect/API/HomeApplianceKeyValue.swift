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
            let parsedValue = element.value.homeConnectParsed
            dictionary[parsedKey] = parsedValue
        }
        
        return dictionary
    }
}
