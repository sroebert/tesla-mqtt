import NIOCore

extension VehicleCommand {
    func wakeUpVehicleWithId(_ vehicleId: Vehicle.ID, using api: TeslaAPI) async throws {
        try await VehicleWaker.shared.wakeUpVehicleWithId(vehicleId, using: api)
    }
}

private actor VehicleWaker {
    
    // MARK: - Types
    
    private enum WakeUpError: String, VehicleCommandError {
        case failedToWakeUpVehicle
    }
    
    // MARK: - Public Vars
    
    static let shared = VehicleWaker()
    
    // MARK: - Private Vars
    
    private static let wakeUpRetries = 10
    private static let wakeUpRetryInterval: TimeAmount = .seconds(3)
    
    private var tasks: [Vehicle.ID: Task<Void, Error>] = [:]
    
    // MARK: - Lifecycle
    
    private init() {}
    
    // MARK: - Wake
    
    func wakeUpVehicleWithId(_ vehicleId: Vehicle.ID, using api: TeslaAPI) async throws {
        if let task = tasks[vehicleId] {
            return try await task.value
        }
        
        let task = Task {
            defer {
                tasks[vehicleId] = nil
            }
            
            var vehicle = try await api.wakeUpVehicleWithId(vehicleId)
            var retries = Self.wakeUpRetries
            
            while vehicle.state != "online" {
                try await Task.sleep(for: Self.wakeUpRetryInterval)
                if let updateVehicle = try? await api.wakeUpVehicleWithId(vehicleId) {
                    vehicle = updateVehicle
                }
                
                retries -= 1
                if retries == 0 {
                    throw WakeUpError.failedToWakeUpVehicle
                }
            }
        }
        tasks[vehicleId] = task
        try await task.value
    }
}
