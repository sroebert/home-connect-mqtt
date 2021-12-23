import Foundation

struct OvenPreheatCommand: HomeApplianceCommand {
    
    // MARK: - Types
    
    private enum Keys {
        static let activeProgram = "BSH.Common.Root.ActiveProgram"
        static let preHeating: JSON = "Cooking.Oven.Program.HeatingMode.PreHeating"
        
        static let setpointTemperature: JSON = "Cooking.Oven.Option.SetpointTemperature"
        static let duration: JSON = "BSH.Common.Option.Duration"
        static let fastPreheat: JSON = "Cooking.Oven.Option.FastPreHeat"
    }
    
    private enum Units {
        static let celsius: JSON = "°C"
        static let seconds: JSON = "seconds"
    }
    
    private struct CommandValue: Decodable {
        var temperature: Int
        var fastPreHeat: Bool?
    }
    
    // MARK: - Public Vars
    
    static let id: String = "power"
    
    let path: String
    let data: JSON
    let event: HomeApplianceEvent
    
    // MARK: - Lifecycle
    
    init(appliance: HomeAppliance, jsonData: Data, decoder: JSONDecoder) throws {
        guard appliance.type == "Oven" else {
            throw HomeApplianceCommandError.unsupportedByAppliance
        }
        
        let value = try decoder.decode(CommandValue.self, from: jsonData)
        
        path = "programs/active"
        data = [
            "key": Keys.preHeating,
            "value": Self.jsonValue(for: value)
        ]
        
        event = HomeApplianceEvent(
            applianceId: appliance.id,
            kind: .notify([
                HomeApplianceEvent.Item(
                    key: Keys.activeProgram,
                    uri: "/api/homeappliances/\(appliance.id)/programs/active",
                    timestamp: Date(),
                    value: Keys.preHeating
                )
            ])
        )
    }
    
    // MARK: - Utils
    
    private static func jsonValue(for value: CommandValue) -> JSON {
        return [
            [
                "key": Keys.setpointTemperature,
                "value": .integer(value.temperature),
                "unit": Units.celsius
            ],
            [
                "key": Keys.duration,
                "value": 900,
                "unit": Units.seconds
            ],
            [
                "key": Keys.fastPreheat,
                "value": .bool(value.fastPreHeat ?? false)
            ]
        ]
    }
}
