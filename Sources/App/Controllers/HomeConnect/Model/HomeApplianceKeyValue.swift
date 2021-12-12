import Vapor

struct HomeApplianceKeyValue: Content {
    
    // MARK: - Public Vars
    
    var key: String
    var value: JSON
}

extension String {
    fileprivate var homeApplianceKeyValueParsed: String {
        let lastComponent = split(separator: ".").last ?? Substring(self)
        return lastComponent.prefix(1).lowercased() + lastComponent.dropFirst()
    }
}

extension Array where Element == HomeApplianceKeyValue {
    var parsedDictionary: [String: JSON] {
        var dictionary: [String: JSON] = [:]
        
        for element in self {
            let parsedKey = element.key.homeApplianceKeyValueParsed
            
            let parsedValue: JSON
            switch element.value {
            case .string(let string):
                parsedValue = .string(string.homeApplianceKeyValueParsed)
                
            default:
                parsedValue = element.value
            }
            
            dictionary[parsedKey] = parsedValue
        }
        
        return dictionary
    }
}
