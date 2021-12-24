import Vapor

struct HomeApplianceEvent {
    
    // MARK: - Public Vars
    
    var applianceId: HomeAppliance.ID
    var kind: Kind
}

extension HomeApplianceEvent {
    enum Kind {
        case keepAlive
        case status([Item])
        case event([Item])
        case notify([Item])
        case disconnected
        case connected
        case paired
        case depaired
        
        var isKeepAlive: Bool {
            switch self {
            case .keepAlive:
                return true
            default:
                return false
            }
        }
    }
    
    struct Item {
        var key: String
        var uri: String?
        var timestamp: Date
        var value: JSON?
    }
}

extension HomeApplianceEvent.Item {
    struct ResponseContainer: Codable {
        
        // MARK: - Public Vars
        
        var items: [Response]
    }
    
    struct Response: Codable {
        
        // MARK: - Public Vars
        
        var key: String
        var uri: String?
        var timestamp: Date
        var value: JSON?
        
        // MARK: - Utils
        
        var parsedEventItem: HomeApplianceEvent.Item {
            return HomeApplianceEvent.Item(
                key: key.homeConnectKeyValueParsed,
                uri: uri,
                timestamp: timestamp,
                value: value?.homeConnectParsed
            )
        }
    }
}

extension EventSourceDelegate.Event {
    var homeApplianceEvent: HomeApplianceEvent? {
        if event == "KEEP-ALIVE" {
            return .init(applianceId: "", kind: .keepAlive)
        }
        
        guard let id = id else {
            return nil
        }
        
        switch event {
        case "STATUS":
            guard let items = homeApplianceEventItems else {
                return nil
            }
            return .init(applianceId: id, kind: .status(items))
            
        case "EVENT":
            guard let items = homeApplianceEventItems else {
                return nil
            }
            return .init(applianceId: id, kind: .event(items))
            
        case "NOTIFY":
            guard let items = homeApplianceEventItems else {
                return nil
            }
            return .init(applianceId: id, kind: .notify(items))
            
        case "DISCONNECTED":
            return .init(applianceId: id, kind: .disconnected)
            
        case "CONNECTED":
            return .init(applianceId: id, kind: .connected)
            
        case "PAIRED":
            return .init(applianceId: id, kind: .paired)
            
        case "DEPAIRED":
            return .init(applianceId: id, kind: .depaired)
            
        default:
            return nil
        }
    }
    
    private var homeApplianceEventItems: [HomeApplianceEvent.Item]? {
        guard
            let data = data,
            let decoder = try? ContentConfiguration.global.requireDecoder(for: .homeConnectJSONAPI)
        else {
            return nil
        }
        
        guard let itemResponses = try? decoder.decode(
            HomeApplianceEvent.Item.ResponseContainer.self,
            from: ByteBuffer(string: data),
            headers: [:]
        ) else {
            return nil
        }
        
        return itemResponses.items.map { $0.parsedEventItem }
    }
}
