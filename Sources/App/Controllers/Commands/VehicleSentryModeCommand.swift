import Foundation

struct VehicleSentryModeCommand: VehicleCommand {
    
    // MARK: - Type
    
    private struct Configuration: Decodable {
        var enabled: Bool
    }
    
    // MARK: - Public Vars
    
    static let id: String = "sentry-mode"
    
    // MARK: - Private Vars
    
    private let configuration: Configuration
    
    // MARK: - Lifecycle
    
    init(jsonData: Data, decoder: JSONDecoder) throws {
        configuration = try decoder.decode(Configuration.self, from: jsonData)
    }
    
    // MARK: - Run
    
    func run(vehicleId: Vehicle.ID, api: TeslaAPI) async throws {
        if configuration.enabled {
            try await wakeUpVehicleWithId(vehicleId, using: api)
        }
        
        try await api.setSentryModeEnabled(configuration.enabled, forVehicleWithId: vehicleId)
    }
}
