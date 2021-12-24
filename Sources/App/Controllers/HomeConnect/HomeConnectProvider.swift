import Vapor
import MQTTNIO

class HomeConnectProvider: LifecycleHandler {
    
    // MARK: - Private Vars
    
    private var manager: HomeConnectManager?
    private var runTask: Task<Void, Error>?
    
    private let mqttURL: URL
    private let mqttCredentials: MQTTConfiguration.Credentials?
    
    // MARK: - Lifecycle
    
    init(mqttURL: URL, mqttCredentials: MQTTConfiguration.Credentials?) {
        self.mqttURL = mqttURL
        self.mqttCredentials = mqttCredentials
    }
    
    // MARK: - LifecycleHandler
    
    func didBoot(_ application: Application) throws {
        let manager = HomeConnectManager(
            application: application,
            api: application.homeConnectAPI,
            mqttURL: mqttURL,
            mqttCredentials: mqttCredentials
        )
        self.manager = manager
        
        Task {
            await manager.start()
        }
    }
    
    func shutdown(_ application: Application) {
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            await self.manager?.stop()
            
            semaphore.signal()
        }
        
        semaphore.wait()
    }
}
