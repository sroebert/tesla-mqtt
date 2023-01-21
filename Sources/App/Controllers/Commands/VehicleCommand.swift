import Foundation

protocol VehicleCommand {
    static var id: String { get }
    
    init(jsonData: Data, decoder: JSONDecoder) throws
    
    func run(vehicleId: Vehicle.ID, api: TeslaAPI) async throws
}

struct VehicleCommandId: Decodable {
    var command: String
}

protocol VehicleCommandError: Error {
    var identifier: String { get }
}

extension VehicleCommandError where Self: RawRepresentable, Self.RawValue == String {
    var identifier: String {
        return rawValue
    }
}

enum VehicleCommandParsingError: String, VehicleCommandError {
    case unknownCommand
    case invalidVehicleId
    case invalidPayload
    case invalidCommandJSON
}

struct VehicleCommandResponse: Encodable {
    var command: String?
    
    var success: Bool
    var errorIdentifier: String?
    var errorMessage: String?
}
