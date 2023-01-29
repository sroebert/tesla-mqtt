import Vapor
import MQTTNIO

actor TeslaManager {
    
    // MARK: - Types
    
    private enum State {
        case idle
        case starting
        case running
        case stopping
    }
    
    private struct CommandRequest {
        var vehicleId: Vehicle.ID
        var commandId: VehicleCommand.ID
        
        var jsonData: Data
        
        var responseTopic: String?
        var responseCorrelationData: Data?
    }
    
    // MARK: - Private Vars
    
    private static let mqttPrefix = "tesla-api"
    private static let vehicleCommandFilter = "\(mqttPrefix)/+/command"
    
    private static let mqttCommands: [VehicleCommand.Type] = [
        VehicleWakeUpCommand.self,
        VehicleStartConditioningCommand.self,
        VehicleStopConditioningCommand.self,
        VehicleChargeLimitCommand.self,
        VehicleSentryModeCommand.self,
    ]
    
    private var application: Application!
    private var api: TeslaAPI!
    private var mqttClient: MQTTClient!
    
    private let mqttJSONEncoder = JSONEncoder()
    private let mqttJSONDecoder = JSONDecoder()
    
    private var state: State = .idle
    
    private var mqttConnectCancellable: MQTTCancellable?
    private var mqttCommandTask: Task<Void, Never>?
    
    // MARK: - Lifecycle
    
    init(
        application: Application,
        mqttURL: URL,
        mqttCredentials: MQTTConfiguration.Credentials?
    ) {
        self.application = application
        self.api = application.teslaAPI
        self.mqttClient = MQTTClient(
            configuration: MQTTConfiguration(
                url: mqttURL,
                for: application.eventLoopGroup,
                clean: false,
                credentials: mqttCredentials,
                willMessage: .init(
                    topic: Self.topic("connected"),
                    payload: .string("false", contentType: "application/json")
                ),
                sessionExpiry: .afterInterval(.hours(24)),
                reconnectMode: .retry(minimumDelay: .seconds(1), maximumDelay: .seconds(3))
            ),
            eventLoopGroupProvider: .shared(application.eventLoopGroup),
            logger: application.logger
        )
    }
    
    // MARK: - Start / Stop
    
    func start() async {
        guard state == .idle else {
            return
        }
        
        state = .starting
        defer {
            state = .running
        }
        
        setupMQTT()
    }
    
    func stop() async {
        guard state == .running else {
            return
        }
        
        state = .stopping
        defer {
            state = .idle
        }
        
        mqttConnectCancellable?.cancel()
        mqttCommandTask?.cancel()
        
        await mqttCommandTask?.value
        
        try? await mqttClient.disconnect(
            sendWillMessage: true,
            sessionExpiry: .atClose
        )
        
        mqttConnectCancellable = nil
        mqttCommandTask = nil
    }
    
    private func setupMQTT() {
        mqttConnectCancellable = mqttClient.whenConnected { [weak self] response in
            if !response.isSessionPresent {
                Task { [self] in
                    try await self?.mqttClient.subscribe(to: Self.vehicleCommandFilter)
                }
            }
            
            Task { [self] in
                try await self?.publishConnected()
            }
        }
        
        Task {
            try await mqttClient.connect()
        }
        
        mqttCommandTask = Task {
            for await message in mqttClient.messages {
                Task {
                    application.logger.trace("Received command request", metadata: [
                        "topic": .string(message.topic),
                        "command": .string(message.payload.string ?? "")
                    ])
                    
                    let request: CommandRequest
                    do {
                        request = try await parseRequest(from: message)
                    } catch {
                        application.logger.error("Failed to parse command request", metadata: [
                            "topic": .string(message.topic),
                            "command": .string(message.payload.string ?? ""),
                            "error": "\(error)"
                        ])
                        return
                    }
                    
                    do {
                        try await perform(request)
                        await sendResponse(for: request, error: nil)
                        
                    } catch {
                        application.logger.error("Failed to execute command", metadata: [
                            "topic": .string(message.topic),
                            "command": .string(message.payload.string ?? ""),
                            "error": "\(error)"
                        ])
                        
                        await sendResponse(for: request, error: error)
                    }
                }
            }
        }
    }
    
    // MARK: - Utils
    
    private static func topic(_ name: String) -> String {
        return "\(mqttPrefix)/\(name)"
    }
    
    private static func topic(vehicleId: Vehicle.ID, _ name: String) -> String {
        return "\(mqttPrefix)/\(vehicleId)/\(name)"
    }
    
    private func publishConnected() async throws {
        try await mqttClient.publish(
            .string("true", contentType: "application/json"),
            to: Self.topic("connected")
        )
    }
    
    // MARK: - Commands
    
    private func parseRequest(from message: MQTTMessage) async throws -> CommandRequest {
        let idComponent = message.topic
            .dropFirst(Self.mqttPrefix.count + 1)
            .prefix { $0 != "/" }
        
        guard let vehicleId = Vehicle.ID(idComponent) else {
            throw VehicleCommandParsingError.invalidVehicleId
        }
        
        guard
            let jsonString = message.payload.string,
            let jsonData = jsonString.data(using: .utf8),
            let request = try? mqttJSONDecoder.decode(VehicleCommandRequest.self, from: jsonData)
        else {
            throw VehicleCommandParsingError.invalidPayload
        }
        
        return CommandRequest(
            vehicleId: vehicleId,
            commandId: request.commandId,
            jsonData: jsonData,
            responseTopic: message.properties.responseTopic,
            responseCorrelationData: message.properties.correlationData
        )
    }
    
    private func perform(_ request: CommandRequest) async throws {
        guard let commandType = Self.mqttCommands.first(where: { $0.id == request.commandId }) else {
            throw VehicleCommandParsingError.unknownCommand
        }
        
        guard
            let command = try? commandType.init(
                jsonData: request.jsonData,
                decoder: mqttJSONDecoder
            )
        else {
            throw VehicleCommandParsingError.invalidCommandJSON
        }
        
        try await command.run(vehicleId: request.vehicleId, api: api)
    }
    
    private func sendResponse(for request: CommandRequest, error: Error?) async {
        guard let responseTopic = request.responseTopic else {
            return
        }
        
        var response = VehicleCommandResponse(
            commandId: request.commandId,
            success: error == nil
        )
        response.errorIdentifier = (error as? VehicleCommandError)?.identifier
        response.errorMessage = error.map { "\($0)" }
        
        guard
            let responseData = try? mqttJSONEncoder.encode(response),
            let responseJSON = String(data: responseData, encoding: .utf8)
        else {
            return
        }
        
        let responseMessage = MQTTMessage(
            topic: responseTopic,
            payload: .string(responseJSON, contentType: "application/json"),
            properties: MQTTMessage.Properties(
                correlationData: request.responseCorrelationData
            )
        )
        try? await mqttClient.publish(responseMessage)
    }
}
