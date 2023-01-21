import Foundation

struct VehicleStartConditioningCommand: VehicleCommand {
    
    // MARK: - Type
    
    private enum SeatMode: String, Decodable {
        case off
        case auto
        case level1
        case level2
        case level3
        
        var seatHeatingModes: [SeatHeatingMode] {
            switch self {
            case .off: return [.auto(enabled: false), .heat(level: 0)]
            case .auto: return [.auto(enabled: true)]
            case .level1: return [.auto(enabled: false), .heat(level: 1)]
            case .level2: return [.auto(enabled: false), .heat(level: 2)]
            case .level3: return [.auto(enabled: false), .heat(level: 3)]
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            guard let mode = SeatMode(rawValue: rawValue) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid seat mode: \(rawValue)"))
            }
            
            self = mode
        }
    }
    
    private struct Configuration: Decodable {
        var driverTemperature: Double
        var driverSeatMode: SeatMode
        
        var passengerTemperature: Double
        var passengerSeatMode: SeatMode
    }
    
    // MARK: - Public Vars
    
    static let id: String = "start-conditioning"
    
    // MARK: - Private Vars
    
    private let configuration: Configuration
    
    // MARK: - Lifecycle
    
    init(jsonData: Data, decoder: JSONDecoder) throws {
        configuration = try decoder.decode(Configuration.self, from: jsonData)
    }
    
    // MARK: - Run
    
    func run(vehicleId: Vehicle.ID, api: TeslaAPI) async throws {
        try await wakeUpVehicleWithId(vehicleId, using: api)
        
        try await api.setPreconditioningEnabled(true, forVehicleWithId: vehicleId)
        
        try await api.setTemperature(
            driver: configuration.driverTemperature,
            passenger: configuration.passengerTemperature,
            forVehicleWithId: vehicleId
        )
        
        for mode in configuration.driverSeatMode.seatHeatingModes {
            try await api.setHeatingMode(mode, for: .frontLeft, forVehicleWithId: vehicleId)
        }
        
        for mode in configuration.passengerSeatMode.seatHeatingModes {
            try await api.setHeatingMode(mode, for: .frontRight, forVehicleWithId: vehicleId)
        }
    }
}
