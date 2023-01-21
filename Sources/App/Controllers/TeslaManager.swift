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
                    do {
                        application.logger.trace("Received command", metadata: [
                            "topic": .string(message.topic),
                            "command": .string(message.payload.string ?? "")
                        ])
                        
                        var command: String? = nil
                        try await handleVehicleCommand(message, command: &command)
                        await sendCommandResponse(for: message, command: command, error: nil)
                        
                    } catch {
                        application.logger.error("Failed to handle command", metadata: [
                            "topic": .string(message.topic),
                            "command": .string(message.payload.string ?? ""),
                            "error": "\(error)"
                        ])
                        
                        await sendCommandResponse(for: message, command: nil, error: error)
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
    
    private func handleVehicleCommand(_ message: MQTTMessage, command: inout String?) async throws {
        let idComponent = message.topic
            .dropFirst(Self.mqttPrefix.count + 1)
            .prefix { $0 != "/" }
        
        guard let vehicleId = Vehicle.ID(idComponent) else {
            throw VehicleCommandParsingError.invalidVehicleId
        }
        
        guard
            let jsonString = message.payload.string,
            let jsonData = jsonString.data(using: .utf8),
            let commandId = try? mqttJSONDecoder.decode(VehicleCommandId.self, from: jsonData)
        else {
            throw VehicleCommandParsingError.invalidPayload
        }
        
        command = commandId.command
        guard let commandType = Self.mqttCommands.first(where: { $0.id == commandId.command }) else {
            throw VehicleCommandParsingError.unknownCommand
        }
        
        guard
            let command = try? commandType.init(
                jsonData: jsonData,
                decoder: mqttJSONDecoder
            )
        else {
            throw VehicleCommandParsingError.invalidCommandJSON
        }
        
        try await command.run(vehicleId: vehicleId, api: api)
    }
    
    private func sendCommandResponse(for message: MQTTMessage, command: String?, error: Error?) async {
        guard let responseTopic = message.properties.responseTopic else {
            return
        }
        
        var response = VehicleCommandResponse(
            command: command,
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
                correlationData: message.properties.correlationData
            )
        )
        try? await mqttClient.publish(responseMessage)
    }
}
