import Foundation

struct HomeAppliancePowerCommand: HomeApplianceCommand {
    
    // MARK: - Types
    
    private enum Keys {
        static let powerState = "BSH.Common.Setting.PowerState"
    }
    
    private enum Values {
        static let on: JSON = "BSH.Common.EnumType.PowerState.On"
        static let off: JSON = "BSH.Common.EnumType.PowerState.Off"
        static let standby: JSON = "BSH.Common.EnumType.PowerState.Standby"
    }
    
    private enum CommandValue: String, Decodable {
        case on
        case off
        
        var isOn: Bool {
            switch self {
            case .on:
                return true
            case .off:
                return false
            }
        }
    }
    
    // MARK: - Public Vars
    
    static let id: String = "power"
    
    let path: String
    let data: JSON
    let event: HomeApplianceEvent
    
    // MARK: - Lifecycle
    
    init(appliance: HomeAppliance, jsonData: Data, decoder: JSONDecoder) throws {
        let value = try decoder.decode(CommandValue.self, from: jsonData)
        let jsonValue = Self.jsonValue(for: value, appliance: appliance)
        
        path = "settings/\(Keys.powerState)"
        data = [
            "key": .string(Keys.powerState),
            "value": jsonValue
        ]
        
        event = HomeApplianceEvent(
            applianceId: appliance.id,
            kind: .notify([
                HomeApplianceEvent.Item.Response(
                    key: Keys.powerState,
                    uri: "/api/homeappliances/\(appliance.id)/settings/\(Keys.powerState)",
                    timestamp: Date(),
                    value: jsonValue
                ).parsedEventItem
            ])
        )
    }
    
    // MARK: - Utils
    
    private static func jsonValue(for value: CommandValue, appliance: HomeAppliance) -> JSON {
        switch value {
        case .on:
            return Values.on
            
        case .off:
            switch appliance.type {
            case "Oven", "CoffeeMachine", "CleaningRobot", "CookProcessor":
                return Values.standby
                
            default:
                return Values.off
            }
        }
    }
}
