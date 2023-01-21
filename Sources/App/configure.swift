import Vapor
import MQTTNIO

public func configure(_ app: Application) throws {
    
    // HTTP
    
    app.http.server.configuration.requestDecompression = .enabled
    app.http.server.configuration.responseCompression = .enabled
    
    // MARK: - JSON
    
    ContentConfiguration.global.use(
        decoder: TeslaAPI.decoder,
        for: .json
    )
    ContentConfiguration.global.use(
        encoder: TeslaAPI.encoder,
        for: .json
    )

    // Routes
    
    try routes(app)
    
    // Refresh Token
    
    if let token = Environment.get("TESLA_REFRESH_TOKEN") {
        app.teslaRefreshToken = token
    }
    
    // Tesla Provider
    
    guard let mqttURL = Environment.get("MQTT_URL").flatMap({ URL(string: $0) }) else {
        fatalError("Missing MQTT URL")
    }

    let mqttCredentials: MQTTConfiguration.Credentials?
    if let username = Environment.get("MQTT_USERNAME"),
       let password = Environment.get("MQTT_PASSWORD") {
        mqttCredentials = .init(username: username, password: password)
    } else {
        mqttCredentials = nil
    }

    app.lifecycle.use(TeslaProvider(
        mqttURL: mqttURL,
        mqttCredentials: mqttCredentials
    ))
}
