import Vapor

func routes(_ app: Application) throws {
    app.get { _ in
        HTTPStatus.noContent
    }
    
    app.get("test") { request in
        try await request.teslaAPI.getVehicles()
    }
}
