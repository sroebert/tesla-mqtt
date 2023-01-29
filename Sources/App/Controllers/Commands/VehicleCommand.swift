import Foundation

protocol VehicleCommand {
    typealias ID = String
    
    static var id: ID { get }
    
    init(jsonData: Data, decoder: JSONDecoder) throws
    
    func run(vehicleId: Vehicle.ID, api: TeslaAPI) async throws
}

struct VehicleCommandRequest: Decodable {
    var commandId: VehicleCommand.ID
    
    // MARK: - Decodable
    
    private enum CodingKeys: String, CodingKey {
        case commandId = "command"
    }
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
    var commandId: VehicleCommand.ID?
    
    var success: Bool
    var errorIdentifier: String?
    var errorMessage: String?
    
    // MARK: - Encodable
    
    private enum CodingKeys: String, CodingKey {
        case commandId = "command"
        case success
        case errorIdentifier
        case errorMessage
    }
}
