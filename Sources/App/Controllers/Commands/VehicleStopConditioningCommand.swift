import Foundation

struct VehicleStopConditioningCommand: VehicleCommand {
    
    // MARK: - Public Vars
    
    static let id: String = "stop-conditioning"
    
    // MARK: - Lifecycle
    
    init(jsonData: Data, decoder: JSONDecoder) throws {
        
    }
    
    // MARK: - Run
    
    func run(vehicleId: Vehicle.ID, api: TeslaAPI) async throws {
        try await api.setPreconditioningEnabled(false, forVehicleWithId: vehicleId)
    }
}
