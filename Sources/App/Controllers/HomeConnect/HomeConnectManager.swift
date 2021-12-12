import Vapor

final class HomeConnectManager: LifecycleHandler {
    
    // MARK: - Types
    
    private struct ApplianceEntry {
        var appliance: HomeAppliance
        var status: [String: JSON]?
        var settings: [String: JSON]?
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
                do {
                    try await run()
                } catch {
                    application.logger.error("Error while running", metadata: [
                        "error": "\(error)"
                    ])
                    await Task.sleep(for: .seconds(15))
                }
            }
        }
    }
    
    func shutdown(_ application: Application) {
        task.cancel()
    }
    
    // MARK: - Run
    
    private func waitForAuthorization() async throws {
        while !Task.isCancelled {
            if try await RefreshToken.query(on: application.db).first() != nil {
                break
            }
            
            await Task.sleep(for: .seconds(5))
        }
    }
    
    private func run() async throws {
        try await waitForAuthorization()
        
        let entries = try await getApplianceEntries()
        print(entries)
    }
    
    // MARK: - Appliances
    
    private func getApplianceEntries() async throws -> [ApplianceEntry] {
        let appliances = try await api.getAppliances()
        
        var entries: [ApplianceEntry] = []
        for appliance in appliances {
            var entry = ApplianceEntry(appliance: appliance)
            if appliance.isConnected {
                entry.status = try await api.getStatus(forApplianceWithId: appliance.id)
                entry.settings = try await api.getSettings(forApplianceWithId: appliance.id)
            }
            
            entries.append(entry)
        }
        
        return entries
    }
}
