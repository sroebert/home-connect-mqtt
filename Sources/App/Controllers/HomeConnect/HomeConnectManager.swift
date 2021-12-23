import Vapor
import MQTTNIO

final class HomeConnectManager: LifecycleHandler {
    
    // MARK: - Types
    
    enum PublishError: Error {
        case jsonEncodingFailed(Error)
        case jsonDataToStringFailed
    }
    
    private enum Topic: CaseIterable {
        case globalCommand
        case applianceCommand
        
        var filter: String {
            switch self {
            case .globalCommand:
                return "\(HomeConnectManager.mqttPrefix)/command"
                
            case .applianceCommand:
                return "\(HomeConnectManager.mqttPrefix)/+/command"
            }
        }
    }
    
    // MARK: - Private Vars
    
    private static let mqttPrefix = "home-connect-test"
    private static let mqttCommands: [HomeApplianceCommand.Type] = [
        HomeAppliancePowerCommand.self,
        OvenPreheatCommand.self
    ]
    
    private var application: Application!
    private var api: HomeConnectAPI!
    
    private let mqttURL: URL
    private let mqttCredentials: MQTTConfiguration.Credentials?
    private var mqttClient: MQTTClient!
    
    private let mqttJSONEncoder = JSONEncoder()
    private let mqttJSONDecoder = JSONDecoder()
    
    private var runTask: Task<Void, Error>?
    private var mqttCommandTask: Task<Void, Never>?
    
    // MARK: - Lifecycle
    
    init(mqttURL: URL, mqttCredentials: MQTTConfiguration.Credentials?) {
        self.mqttURL = mqttURL
        self.mqttCredentials = mqttCredentials
    }
    
    // MARK: - LifecycleHandler
    
    func willBoot(_ application: Application) throws {
        self.application = application
        self.api = application.homeConnectAPI
        
        self.mqttClient = MQTTClient(
            configuration: MQTTConfiguration(
                url: mqttURL,
                clean: false,
                credentials: mqttCredentials,
                willMessage: .init(topic: topic("connected"), payload: "{}"),
                sessionExpiry: .afterInterval(.hours(24))
            ),
            eventLoopGroupProvider: .shared(application.eventLoopGroup),
            logger: application.logger
        )
    }
    
    func didBoot(_ application: Application) throws {
        runTask = Task {
            while !Task.isCancelled {
                try await run()
            }
        }
    }
    
    func shutdown(_ application: Application) {
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            self.runTask?.cancel()
            try? await self.runTask?.value
        
            self.mqttCommandTask?.cancel()
            await self.mqttCommandTask?.value
            
            try? await self.mqttClient.disconnect(
                sendWillMessage: true,
                sessionExpiry: .atClose
            )
            
            semaphore.signal()
        }
        
        semaphore.wait()
    }
    
    // MARK: - Run
    
    private func waitForAuthorization() async {
        while !Task.isCancelled {
            let refreshToken = try? await RefreshToken.query(on: application.db).first()
            if refreshToken != nil {
                break
            }
            
            try? await Task.sleep(for: .seconds(5))
        }
    }
    
    private func run() async throws {
        await waitForAuthorization()
        
        let manager = HomeApplianceStateManager(api: api) { [weak self] states, applianceId, updateType in
            self?.onUpdate(states: states, applianceId: applianceId, updateType: updateType)
        }
        
        setupMQTT(for: manager)
        await performRunLoop(for: manager)
    }
    
    private func performRunLoop(for manager: HomeApplianceStateManager) async {
        while !Task.isCancelled {
            do {
                await manager.removeAllAppliances()
                try await fetchAppliances(for: manager)
                try await monitorEvents(for: manager)
            } catch {
                application.logger.error("Failed to monitor events", metadata: [
                    "error": "\(error)"
                ])
            }
            
            application.logger.info("Retrying to monitor in 30 seconds")
            try? await Task.sleep(for: .seconds(30))
        }
    }
    
    // MARK: - Appliances
    
    private func fetchAppliances(for manager: HomeApplianceStateManager) async throws {
        application.logger.notice("Retrieving appliances...")
        let appliances = try await api.getAppliances()
        
        application.logger.notice("Found appliances", metadata: [
            "appliances": .array(appliances.map { .string("\($0.name) (\($0.id))") })
        ])
        
        for appliance in appliances {
            try await manager.insert(appliance)
        }
        
        application.logger.notice("Fetched all appliance details")
    }
    
    // MARK: - Events
    
    private func monitorEvents(for manager: HomeApplianceStateManager) async throws {
        application.logger.notice("Monitoring events...")
        
        for try await event in application.homeConnectAPI.events {
            application.logger.trace("Received event", metadata: [
                "event": "\(event)"
            ])
            
            Task {
                await process(event, for: manager)
            }
        }
    }
    
    private func process(_ event: HomeApplianceEvent, for manager: HomeApplianceStateManager) async {
        do {
            switch event.kind {
            case .keepAlive:
                application.logger.trace("Received keep alive")
                
            case .status(let items), .notify(let items):
                try await manager.process(items, forApplianceWithId: event.applianceId)
                
            case .event(let items):
                for item in items {
                    Task {
                        do {
                            try await publish(
                                eventWithName: item.key,
                                value: item.value,
                                forApplianceWithId: event.applianceId
                            )
                        } catch {
                            application.logger.error("Failed to publish event", metadata: [
                                "error": "\(error)"
                            ])
                        }
                    }
                }
                
            case .connected:
                try await manager.connect(applianceWithId: event.applianceId)
                
            case .disconnected:
                try await manager.disconnect(applianceWithId: event.applianceId)
                
            case .paired:
                try await manager.insertAppliance(withId: event.applianceId)
                
            case .depaired:
                await manager.removeAppliance(withId: event.applianceId)
            }
        } catch {
            application.logger.error("Failed to process event", metadata: [
                "event": "\(event)",
                "error": "\(error)"
            ])
        }
    }
    
    private func onUpdate(
        states: [HomeAppliance.ID: HomeApplianceState],
        applianceId: HomeAppliance.ID?,
        updateType: HomeApplianceUpdateType
    ) {
        Task {
            do {
                try await publishUpdate(
                    states: states,
                    applianceId: applianceId,
                    updateType: updateType
                )
            } catch {
                application.logger.error("Failed to publish update", metadata: [
                    "error": "\(error)"
                ])
            }
        }
    }
    
    // MARK: - MQTT
    
    private func setupMQTT(for manager: HomeApplianceStateManager) {
        mqttClient.whenConnected { [weak self] response in
            guard !response.isSessionPresent else {
                return
            }
            
            Task { [self] in
                try await self?.mqttClient.subscribe(to: Topic.allCases.map(\.filter))
            }
        }
        
        Task {
            try await mqttClient.connect()
        }
        
        mqttCommandTask = Task {
            for await message in mqttClient.messages {
                Task {
                    do {
                        if message.topic.matchesMqttTopicFilter(Topic.globalCommand.filter) {
                            try await handleGlobalCommand(message, for: manager)
                        } else if message.topic.matchesMqttTopicFilter(Topic.applianceCommand.filter) {
                            try await handleApplianceCommand(message, for: manager)
                        }
                    } catch {
                        application.logger.error("Failed to handle command", metadata: [
                            "topic": .string(message.topic),
                            "command": .string(message.payload.string ?? ""),
                            "error": "\(error)"
                        ])
                    }
                }
            }
        }
    }
    
    private func topic(_ name: String) -> String {
        return "\(Self.mqttPrefix)/\(name)"
    }
    
    private func topic(applianceId: HomeAppliance.ID, _ name: String) -> String {
        return "\(Self.mqttPrefix)/\(applianceId)/\(name)"
    }
    
    private func payload<E: Encodable>(for encodable: E?) throws -> MQTTPayload {
        guard let encodable = encodable else {
            return .string("null", contentType: "application/json")
        }
        
        let jsonData: Data
        do {
            jsonData = try mqttJSONEncoder.encode(encodable)
        } catch {
            throw PublishError.jsonEncodingFailed(error)
        }
        
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw PublishError.jsonDataToStringFailed
        }
        
        return .string(jsonString, contentType: "")
    }
    
    private func publish(_ states: [HomeAppliance.ID: HomeApplianceState]) async throws {
        for applianceId in states.keys {
            try await publish(states, applianceId: applianceId)
        }
    }
    
    private func publish(_ states: [HomeAppliance.ID: HomeApplianceState], applianceId: HomeAppliance.ID) async throws {
        let updateTypes: [HomeApplianceUpdateType] = [
            .info, .status, .settings, .activeProgram, .selectedProgram
        ]
        
        for updateType in updateTypes {
            try await publishUpdate(states: states, applianceId: applianceId, updateType: updateType)
        }
    }
    
    private func publishUpdate(
        states: [HomeAppliance.ID: HomeApplianceState],
        applianceId: HomeAppliance.ID?,
        updateType: HomeApplianceUpdateType
    ) async throws {
        let topic: String
        let payload: MQTTPayload
        
        if updateType == .isConnected {
            topic = self.topic("connected")
            
            var connectionStates: [HomeAppliance.ID: Bool] = [:]
            for (id, state) in states {
                connectionStates[id] = state.appliance.isConnected
            }
            payload = try self.payload(for: connectionStates)
        } else {
            guard let applianceId = applianceId, let state = states[applianceId] else {
                return
            }
            
            switch updateType {
            case .isConnected:
                return
                
            case .info:
                topic = self.topic(applianceId: state.appliance.id, "info")
                payload = try self.payload(for: [
                    "id": state.appliance.id,
                    "name": state.appliance.name,
                    "brand": state.appliance.brand,
                    "type": state.appliance.type,
                    "vib": state.appliance.vib,
                    "eNumber": state.appliance.eNumber
                ])
                
            case .status:
                topic = self.topic(applianceId: state.appliance.id, "status")
                payload = try self.payload(for: state.status)
                
            case .settings:
                topic = self.topic(applianceId: state.appliance.id, "settings")
                payload = try self.payload(for: state.settings)
                
            case .activeProgram:
                topic = self.topic(applianceId: state.appliance.id, "programs/active")
                payload = try self.payload(for: state.activeProgram)
                
            case .selectedProgram:
                topic = self.topic(applianceId: state.appliance.id, "programs/selected")
                payload = try self.payload(for: state.selectedProgram)
            }
        }
        
        try await mqttClient.publish(payload, to: topic)
    }
    
    private func publish(
        eventWithName name: String,
        value: JSON?,
        forApplianceWithId applianceId: String
    ) async throws {
        try await mqttClient.publish(
            payload(for: value),
            to: topic(applianceId: applianceId, "events/\(name)")
        )
    }
    
    private func handleGlobalCommand(_ message: MQTTMessage, for manager: HomeApplianceStateManager) async throws {
        let command = message.payload.string?.lowercased()
        switch command {
        case "announce":
            let states = await manager.states
            try await publishUpdate(states: states, applianceId: nil, updateType: .isConnected)
            try await publish(states)
            
        default:
            throw HomeApplianceCommandError.unknownCommand
        }
    }
    
    private func handleApplianceCommand(_ message: MQTTMessage, for manager: HomeApplianceStateManager) async throws {
        let idComponent = message.topic
            .dropFirst(Self.mqttPrefix.count + 1)
            .prefix { $0 != "/" }
        
        let applianceId = HomeAppliance.ID(idComponent)
        
        let states = await manager.states
        guard let state = states[applianceId] else {
            throw HomeApplianceCommandError.unknownAppliance
        }
        
        guard
            let jsonString = message.payload.string,
            let jsonData = jsonString.data(using: .utf8),
            let commands = try? mqttJSONDecoder.decode([String: JSON].self, from: jsonData)
        else {
            throw HomeApplianceCommandError.invalidPayload
        }
        
        for (id, json) in commands {
            guard let commandType = Self.mqttCommands.first(where: { $0.id == id }) else {
                throw HomeApplianceCommandError.unknownCommand
            }
            
            guard
                let jsonData = try? mqttJSONEncoder.encode(json),
                let command = try? commandType.init(
                    appliance: state.appliance,
                    jsonData: jsonData,
                    decoder: mqttJSONDecoder
                )
            else {
                throw HomeApplianceCommandError.invalidCommandJSON
            }
            
            try await perform(command, for: state, manager: manager)
        }
    }
    
    private func perform(
        _ command: HomeApplianceCommand,
        for state: HomeApplianceState,
        manager: HomeApplianceStateManager
    ) async throws {
        let path = command.path
        let data = command.data
        
        try await api.updateAppliance(withId: state.appliance.id, path: path, data: data)
        
        let event = command.event
        await process(event, for: manager)
    }
}
