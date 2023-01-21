import Vapor
import AsyncHTTPClient

struct TeslaTokenAPI {
    
    // MARK: - Private Vars
    
    private static let baseURL = "https://auth.tesla.com/oauth2/v3/"
    
    private static let tokenManager = TokenManager()
    
    private let application: Application
    private let client: Client
    
    // MARK: - Lifecycle
    
    init(
        application: Application,
        client: Client
    ) {
        self.application = application
        self.client = client
    }
    
    // MARK: - Utils
    
    private func url(forPath path: String) -> URI {
        return URI(string: Self.baseURL + path)
    }
    
    // MARK: - Public
    
    var accessToken: AccessToken {
        get async throws {
            try await Self.tokenManager.getAccessToken {
                try await self.refreshToken()
            }
        }
    }
    
    func invalidateAccessToken() async {
        await Self.tokenManager.invalidate()
    }
    
    // MARK: - Refresh Token
    
    private func refreshToken() async throws -> AccessToken {
        let refreshToken = application.teslaRefreshToken
        
        let response: ClientResponse
        do {
            response = try await client.post(url(forPath: "token")) { request in
                try request.content.encode(RefreshTokenRequest(refreshToken: refreshToken))
            }
        } catch {
            throw APIError.connectionError(error)
        }
        
        guard response.status == .ok else {
            throw APIError.apiError(response.status, response.body.map(String.init))
        }
        
        let token = try response.content.decode(Token.self)
        if token.refreshToken != refreshToken {
            application.logger.error("Refresh token changed after refresh")
        }
        
        let accessToken = AccessToken(
            token: token.accessToken,
            expires: Date(timeIntervalSinceNow: TimeInterval(token.expiresIn))
        )
        
        await Self.tokenManager.setAccessToken(accessToken)
        
        return accessToken
    }
}

extension Application {
    var teslaTokenAPI: TeslaTokenAPI {
        return TeslaTokenAPI(
            application: self,
            client: client
        )
    }
}

extension Request {
    var teslaTokenAPI: TeslaTokenAPI {
        return TeslaTokenAPI(
            application: application,
            client: client
        )
    }
}

