import Foundation

protocol HomeApplianceCommand {
    static var id: String { get }
    
    init(appliance: HomeAppliance, jsonData: Data, decoder: JSONDecoder) throws
   
    var path: String { get }
    var data: JSON { get }
    
    var event: HomeApplianceEvent { get }
}

extension HomeApplianceCommand {
    func isSupported(by appliance: HomeAppliance) -> Bool {
        return true
    }
}

enum HomeApplianceCommandError: Error {
    case unknownCommand
    case unknownAppliance
    case invalidPayload
    case unsupportedByAppliance
    case invalidCommandJSON
}
