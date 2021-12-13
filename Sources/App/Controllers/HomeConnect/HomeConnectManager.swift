import Vapor

final class HomeConnectManager: LifecycleHandler {
    
    // MARK: - Types
    
    private struct ApplianceEntry {
        var appliance: HomeAppliance
        
        var status: [String: JSON]?
        var settings: [String: JSON]?
        
        var activeProgram: HomeAppliance.Program?
        var selectedProgram: HomeAppliance.Program?
    }
    
    // MARK: - Private Vars
    
    private var application: Application!
    private var api: HomeConnectAPI!
    private var task: Task<Void, Never>!
    
    // MARK: - LifecycleHandler
    
    func willBoot(_ application: Application) throws {
        self.application = application
        self.api = application.homeConnectAPI
    }
    
    func didBoot(_ application: Application) throws {
        task = Task {
            while !Task.isCancelled {
                await run()
            }
        }
    }
    
    func shutdown(_ application: Application) {
        task.cancel()
    }
    
    // MARK: - Run
    
    private func waitForAuthorization() async {
        while !Task.isCancelled {
            let refreshToken = try? await RefreshToken.query(on: application.db).first()
            if refreshToken != nil {
                break
            }
            
            await Task.sleep(for: .seconds(5))
        }
    }
    
    private func run() async {
        await waitForAuthorization()
        
        let entries = await getApplianceEntriesUntilSucceeded()
        await monitorEventsUntilCancelled(for: entries)
    }
    
    // MARK: - Appliances
    
    private func getApplianceEntriesUntilSucceeded() async -> [ApplianceEntry] {
        while !Task.isCancelled {
            do {
                return try await getApplianceEntries()
            } catch {
                application.logger.error("Failed to retrieve appliances", metadata: [
                    "error": "\(error)"
                ])
            }
            
            await Task.sleep(for: .seconds(30))
        }
        
        return []
    }
    
    private func getApplianceEntries() async throws -> [ApplianceEntry] {
        application.logger.notice("Retrieving appliances...")
        let appliances = try await api.getAppliances()
        
        application.logger.notice("Found appliances", metadata: [
            "appliances": .array(appliances.map { .string("\($0.name) (\($0.id))") })
        ])
        
        var entries: [ApplianceEntry] = []
        for appliance in appliances {
            if appliance.isConnected {
                async let status = api.getStatus(forApplianceWithId: appliance.id)
                async let settings = api.getSettings(forApplianceWithId: appliance.id)
                async let activeProgram = api.getActiveProgram(forApplianceWithId: appliance.id)
                async let selectedProgram = api.getSelectedProgram(forApplianceWithId: appliance.id)
                
                try await entries.append(ApplianceEntry(
                    appliance: appliance,
                    status: status,
                    settings: settings,
                    activeProgram: activeProgram,
                    selectedProgram: selectedProgram
                ))
            } else {
                entries.append(ApplianceEntry(appliance: appliance))
            }
        }
        
        application.logger.notice("Fetched all appliance details")
        return entries
    }
    
    // MARK: - Events
    
    private func monitorEventsUntilCancelled(for entries: [ApplianceEntry]) async {
        while !Task.isCancelled {
            do {
                try await monitorEvents(for: entries)
            } catch {
                application.logger.error("Failed to monitor events", metadata: [
                    "error": "\(error)"
                ])
            }
            
            await Task.sleep(for: .seconds(30))
        }
    }
    
    private func monitorEvents(for entries: [ApplianceEntry]) async throws {
        for try await event in application.homeConnectAPI.events {
            print(event)
        }
    }
}
