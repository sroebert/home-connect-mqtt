import Vapor

extension HomeAppliance {
    struct Program: Encodable {
        
        // MARK: - Public Vars
        
        var name: String
        var options: [String: JSON]
        
        // MARK: - Raw
        
        struct Response: Content {
            
            // MARK: - Public Vars
            
            var key: String
            var options: [HomeApplianceKeyValue]?
            
            // MARK: - Utils
            
            var parsedProgram: Program {
                return Program(
                    name: key.homeConnectKeyValueParsed,
                    options: options?.parsedDictionary ?? [:]
                )
            }
        }
    }
}
