import Foundation

struct VehicleWakeUpCommand: VehicleCommand {
    
    // MARK: - Public Vars
    
    static let id: String = "wake-up"
    
    // MARK: - Lifecycle
    
    init(jsonData: Data, decoder: JSONDecoder) throws {
        
    }
    
    // MARK: - Run
    
    func run(vehicleId: Vehicle.ID, api: TeslaAPI) async throws {
        try await wakeUpVehicleWithId(vehicleId, using: api)
    }
}
