import Vapor
import AsyncHTTPClient

struct EmptyResult: Content {
    
}

struct TeslaAPI {
    
    // MARK: - Types
    
    enum Error: Swift.Error {
        case seatDoesNotSupportAutoMode
        case invalidSeatLevel
    }
    
    // MARK: - Public Vars
    
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
    
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
    
    // MARK: - Private Vars
    
    private static let baseURL = "https://owner-api.teslamotors.com/"
    
    static let userAgent = "TeslaApp/4.10.0"
    
    private let application: Application
    private let tokenAPI: TeslaTokenAPI
    private let client: Client
    
    // MARK: - Lifecycle
    
    init(
        application: Application,
        tokenAPI: TeslaTokenAPI,
        client: Client
    ) {
        self.application = application
        self.tokenAPI = tokenAPI
        self.client = client
    }
    
    // MARK: - Utils
    
    private func url(forPath path: String) -> URI {
        return URI(string: Self.baseURL + path)
    }
    
    private func request(_ method: HTTPMethod, _ path: String) async throws -> ClientRequest {
        let accessToken = try await tokenAPI.accessToken
        
        let url = url(forPath: path)
        var request = ClientRequest(method: method, url: url, headers: [:], body: nil)
        
        request.headers.replaceOrAdd(name: .userAgent, value: Self.userAgent)
        request.headers.bearerAuthorization = .init(token: accessToken.token)
        
        return request
    }
    
    private func `get`<Result: Content>(
        _ path: String,
        at keyPath: CodingKeyRepresentable...
    ) async throws -> Result {
        let request = try await request(.GET, path)
        let response = try await perform(request)
        return try response.content.get(Result.self, at: keyPath)
    }
    
    private func perform(
        _ path: String,
        method: HTTPMethod,
        data: JSON?
    ) async throws {
        var request = try await request(method, path)
        
        if let data {
            do {
                try request.content.encode(data, as: .json)
            } catch {
                throw APIError.encodingError(error)
            }
        }
        
        try await perform(request)
    }
    
    private func post(_ path: String, data: JSON? = nil) async throws {
        try await perform(path, method: .POST, data: data)
    }
    
    private func put(_ path: String, data: JSON? = nil) async throws {
        try await perform(path, method: .PUT, data: data)
    }
    
    private func perform<Result: Content>(
        _ path: String,
        method: HTTPMethod,
        data: JSON?,
        at keyPath: [CodingKeyRepresentable]
    ) async throws -> Result {
        var request = try await request(method, path)
        
        if let data {
            do {
                try request.content.encode(data, as: .json)
            } catch {
                throw APIError.encodingError(error)
            }
        }
        
        let response = try await perform(request)
        return try response.content.get(Result.self, at: keyPath)
    }
    
    private func post<Result: Content>(
        _ path: String,
        data: JSON? = nil,
        at keyPath: CodingKeyRepresentable...
    ) async throws -> Result {
        try await perform(path, method: .POST, data: data, at: keyPath)
    }
    
    private func put<Result: Content>(
        _ path: String,
        data: JSON? = nil,
        at keyPath: CodingKeyRepresentable...
    ) async throws -> Result {
        try await perform(path, method: .PUT, data: data, at: keyPath)
    }
    
    @discardableResult
    private func perform(_ request: ClientRequest) async throws -> ClientResponse {
        let response: ClientResponse
        do {
            response = try await client.send(request)
        } catch {
            throw APIError.connectionError(error)
        }
        
        guard (200..<300).contains(response.status.code) else {
            if response.status == .unauthorized {
                await tokenAPI.invalidateAccessToken()
            }
            
            throw APIError.apiError(
                response.status,
                response.body.map(String.init)
            )
        }
        
        return response
    }
    
    // MARK: - Validation
    
    private func validateSeatHeatCoolLevel(_ level: Int) throws {
        guard level >= 0 && level <= 3 else {
            throw Error.invalidSeatLevel
        }
    }
    
    // MARK: - API
    
    func getVehicles() async throws -> [Vehicle] {
        try await get("api/1/vehicles", at: "response")
    }
    
    func getState(_ vehicleId: Vehicle.ID) async throws -> EmptyResult {
        try await get("/api/1/vehicles/\(vehicleId)/data_request/climate_state", at: "response")
    }
    
    func wakeUpVehicleWithId(_ vehicleId: Vehicle.ID) async throws -> Vehicle {
        try await post("api/1/vehicles/\(vehicleId)/wake_up", at: "response")
    }
    
    func setSentryModeEnabled(_ enabled: Bool, forVehicleWithId vehicleId: Vehicle.ID) async throws {
        try await post("api/1/vehicles/\(vehicleId)/command/set_sentry_mode", data: [
            "on": .bool(enabled),
        ])
    }
    
    func setChargeLimit(_ limit: Int, forVehicleWithId vehicleId: Vehicle.ID) async throws {
        try await post("api/1/vehicles/\(vehicleId)/command/set_charge_limit", data: [
            "percent": .integer(limit),
        ])
    }
    
    func setPreconditioningEnabled(_ enabled: Bool, forVehicleWithId vehicleId: Vehicle.ID) async throws {
        if enabled {
            try await post("api/1/vehicles/\(vehicleId)/command/auto_conditioning_start")
        } else {
            try await post("api/1/vehicles/\(vehicleId)/command/auto_conditioning_stop")
        }
    }
    
    func setTemperature(
        driver driverTemperature: Double,
        passenger passengerTemperature: Double,
        forVehicleWithId vehicleId: Vehicle.ID
    ) async throws {
        try await post("api/1/vehicles/\(vehicleId)/command/set_temps", data: [
            "driver_temp": .double(driverTemperature),
            "passenger_temp": .double(passengerTemperature),
        ])
    }
    
    func setHeatingMode(
        _ mode: SeatHeatingMode,
        for seat: Seat,
        forVehicleWithId vehicleId: Vehicle.ID
    ) async throws {
        switch mode {
        case .heat(let level):
            try validateSeatHeatCoolLevel(level)
            try await post("api/1/vehicles/\(vehicleId)/command/remote_seat_heater_request", data: [
                "heater": .integer(seat.heatCoolId),
                "level": .integer(level),
            ])
            
        case .cool(let level):
            try validateSeatHeatCoolLevel(level)
            try await post("api/1/vehicles/\(vehicleId)/command/remote_seat_cooler_request", data: [
                "seat_position": .integer(seat.heatCoolId),
                "seat_cooler_level": .integer(level),
            ])
            
        case .auto(let enabled):
            guard let seatId = seat.autoId else {
                throw Error.seatDoesNotSupportAutoMode
            }
            
            try await post("api/1/vehicles/\(vehicleId)/command/remote_auto_seat_climate_request", data: [
                "auto_seat_position": .integer(seatId),
                "auto_climate_on": .bool(enabled),
            ])
        }
    }
}

extension Application {
    var teslaAPI: TeslaAPI {
        return TeslaAPI(
            application: self,
            tokenAPI: teslaTokenAPI,
            client: client
        )
    }
}

extension Request {
    var teslaAPI: TeslaAPI {
        return TeslaAPI(
            application: application,
            tokenAPI: teslaTokenAPI,
            client: client
        )
    }
}
