actor HomeApplianceStateManager {
    
    // MARK: - Types
    
    struct DataUpdateError: Error {
        var errors: [Error]
    }
    
    private struct UpdateTaskID: Hashable {
        var applianceId: HomeAppliance.ID
        var updateType: HomeApplianceUpdateType
    }
    
    typealias UpdateHandler = @Sendable ([HomeAppliance.ID: HomeApplianceState], HomeAppliance.ID, HomeApplianceUpdateType) -> Void
    
    private struct StateUpdateResult {
        var updated = Set<HomeApplianceUpdateType>()
        var fetchRequired = Set<HomeApplianceUpdateType>()
    }
    
    // MARK: - Public Vars
    
    private(set) var states: [HomeAppliance.ID: HomeApplianceState] = [:]
    
    // MARK: - Private Vars
    
    private let api: HomeConnectAPI
    private let onUpdate: UpdateHandler
    
    private var fetchTasks: [HomeAppliance.ID: Task<Void, Error>] = [:]
    private var updateTasks: [UpdateTaskID: Task<Void, Error>] = [:]
    
    // MARK: - Lifecycle
    
    init(api: HomeConnectAPI, onUpdate: @escaping UpdateHandler) {
        self.api = api
        self.onUpdate = onUpdate
    }
    
    // MARK: - Utils
    
    private func fetch(
        _ updateTypes: Set<HomeApplianceUpdateType>,
        forApplianceWithId applianceId: HomeAppliance.ID
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for updateType in updateTypes {
                group.addTask {
                    try await self.fetch(updateType, forApplianceWithId: applianceId)
                }
            }
            
            var errors: [Error] = []
            while let result = await group.nextResult() {
                if case .failure(let error) = result {
                    errors.append(error)
                }
            }
            
            if !errors.isEmpty {
                throw DataUpdateError(errors: errors)
            }
        }
    }
    
    private func fetch(
        _ updateType: HomeApplianceUpdateType,
        forApplianceWithId applianceId: HomeAppliance.ID
    ) async throws {
        let taskId = UpdateTaskID(applianceId: applianceId, updateType: updateType)
        let task = updateTasks[taskId] ?? Task {
            defer {
                updateTasks.removeValue(forKey: taskId)
            }
            
            try await fetchAndUpdate(updateType, forApplianceWithId: applianceId)
        }
        
        updateTasks[taskId] = task
        
        try await task.value
    }
    
    private func fetchAndUpdate(
        _ updateType: HomeApplianceUpdateType,
        forApplianceWithId applianceId: HomeAppliance.ID
    ) async throws {
        
        func update<Data>(
            _ keyPath: WritableKeyPath<HomeApplianceState, Data>,
            using fetch: (HomeAppliance.ID) async throws -> Data
        ) async throws {
            let data = try await fetch(applianceId)
            
            try Task.checkCancellation()
            guard var state = states[applianceId], state.appliance.isConnected else {
                return
            }
            
            state[keyPath: keyPath] = data
            states[applianceId] = state
            
            onUpdate(states, applianceId, updateType)
        }
        
        switch updateType {
        case .info, .isConnected:
            try await update(\.appliance, using: api.getAppliance)
            
        case .status:
            try await update(\.status, using: api.getStatus)
            
        case .settings:
            try await update(\.settings, using: api.getSettings)
            
        case .activeProgram:
            try await update(\.activeProgram, using: api.getActiveProgram)
            
        case .selectedProgram:
            try await update(\.selectedProgram, using: api.getSelectedProgram)
        }
    }
    
    // MARK: - Manage
    
    func removeAllAppliances() {
        fetchTasks.values.forEach { $0.cancel() }
        updateTasks.values.forEach { $0.cancel() }
        
        states.removeAll()
        
        for id in states.keys {
            onUpdate(states, id, .isConnected)
        }
    }
    
    func insertAppliance(withId applianceId: HomeAppliance.ID) async throws {
        let task = fetchTasks[applianceId] ?? Task {
            defer {
                fetchTasks.removeValue(forKey: applianceId)
            }
            
            let appliance = try await api.getAppliance(withId: applianceId)
            
            try Task.checkCancellation()
            try await insert(appliance)
        }
        
        fetchTasks[applianceId] = task
        
        try await task.value
    }
    
    func insert(_ appliance: HomeAppliance) async throws {
        let existingState = states[appliance.id]
        
        var state = existingState ?? HomeApplianceState(appliance: appliance)
        state.appliance = appliance
        states[appliance.id] = state
        
        if existingState == nil {
            onUpdate(states, appliance.id, .info)
        }
        
        if existingState?.appliance.isConnected != appliance.isConnected {
            onUpdate(states, appliance.id, .isConnected)
        }
        
        if appliance.isConnected {
            try await fetch([
                .status,
                .settings,
                .activeProgram,
                .selectedProgram
            ], forApplianceWithId: appliance.id)
        }
    }
    
    func removeAppliance(withId applianceId: HomeAppliance.ID) {
        states.removeValue(forKey: applianceId)
        
        onUpdate(states, applianceId, .isConnected)
    }
    
    func connect(applianceWithId applianceId: HomeAppliance.ID) async throws {
        guard var state = states[applianceId] else {
            try await insertAppliance(withId: applianceId)
            return
        }
        
        guard !state.appliance.isConnected else {
            return
        }
        
        state.appliance.isConnected = true
        states[applianceId] = state
        onUpdate(states, applianceId, .isConnected)
    }
    
    func disconnect(applianceWithId applianceId: HomeAppliance.ID) async throws {
        guard var state = states[applianceId] else {
            try await insertAppliance(withId: applianceId)
            return
        }
        
        guard state.appliance.isConnected else {
            return
        }
        
        state.appliance.isConnected = false
        states[applianceId] = state
        onUpdate(states, applianceId, .isConnected)
    }
    
    func process(_ items: [HomeApplianceEvent.Item], forApplianceWithId applianceId: HomeAppliance.ID) async throws {
        guard var state = states[applianceId] else {
            try await insertAppliance(withId: applianceId)
            return
        }
        
        var result = StateUpdateResult()
        let urlPrefix = "/api/homeappliances/\(applianceId)"
        for item in items {
            guard let uri = item.uri else {
                continue
            }
            
            if uri.hasPrefix("\(urlPrefix)/status/") {
                updateOptions(.status, with: item, result: &result) {
                    state.status
                } set: {
                    state.status = $0
                }
            } else if uri.hasPrefix("\(urlPrefix)/settings/") {
                updateOptions(.settings, with: item, result: &result) {
                    state.settings
                } set: {
                    state.settings = $0
                }
            } else if uri == "\(urlPrefix)/programs/active" {
                if item.value != nil {
                    result.fetchRequired.insert(.activeProgram)
                } else if state.activeProgram != nil {
                    state.activeProgram = nil
                    result.updated.insert(.activeProgram)
                }
            } else if uri.hasPrefix("\(urlPrefix)/programs/active/options/") {
                updateOptions(.settings, with: item, result: &result) {
                    state.activeProgram?.options
                } set: {
                    state.activeProgram?.options = $0
                }
            } else if uri == "\(urlPrefix)/programs/selected" {
                if item.value != nil {
                    result.fetchRequired.insert(.selectedProgram)
                } else if state.activeProgram != nil {
                    state.activeProgram = nil
                    result.updated.insert(.selectedProgram)
                }
            } else if uri.hasPrefix("\(urlPrefix)/programs/selected/options/") {
                updateOptions(.settings, with: item, result: &result) {
                    state.selectedProgram?.options
                } set: {
                    state.selectedProgram?.options = $0
                }
            }
        }
        
        states[applianceId] = state
        
        for updateType in result.updated {
            onUpdate(states, applianceId, updateType)
        }
        
        guard !result.fetchRequired.isEmpty else {
            return
        }
        
        try await fetch(result.fetchRequired, forApplianceWithId: applianceId)
    }
    
    private func updateOptions(
        _ updateType: HomeApplianceUpdateType,
        with item: HomeApplianceEvent.Item,
        result: inout StateUpdateResult,
        get: () -> [String: JSON]?,
        set: ([String: JSON]) -> Void
    ) {
        guard var dictionary = get() else {
            // If data does not exist, it requires a fetch
            result.fetchRequired.insert(updateType)
            return
        }
        
        // Only update if value is different
        guard dictionary[item.key] != item.value else {
            return
        }
        
        dictionary[item.key] = item.value
        set(dictionary)
        
        result.updated.insert(updateType)
    }
}
