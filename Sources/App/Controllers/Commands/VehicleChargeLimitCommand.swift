import Foundation

struct VehicleChargeLimitCommand: VehicleCommand {
    
    // MARK: - Type
    
    private enum ChargeLimitError: String, VehicleCommandError {
        case invalidChargeLimit
    }
    
    private struct Configuration: Decodable {
        var limit: Int
    }
    
    // MARK: - Public Vars
    
    static let id: String = "charge-limit"
    
    // MARK: - Private Vars
    
    private let configuration: Configuration
    
    // MARK: - Lifecycle
    
    init(jsonData: Data, decoder: JSONDecoder) throws {
        configuration = try decoder.decode(Configuration.self, from: jsonData)
    }
    
    // MARK: - Run
    
    func run(vehicleId: Vehicle.ID, api: TeslaAPI) async throws {
        guard configuration.limit >= 1 && configuration.limit <= 100 else {
            throw ChargeLimitError.invalidChargeLimit
        }
        
        try await wakeUpVehicleWithId(vehicleId, using: api)
        
        try await api.setChargeLimit(configuration.limit, forVehicleWithId: vehicleId)
    }
}
