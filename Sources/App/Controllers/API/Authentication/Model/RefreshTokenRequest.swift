import Vapor

struct RefreshTokenRequest: Content {
    
    // MARK: - Public Vars
    
    var refreshToken: String
    
    var grantType = "refresh_token"
    var clientId = "ownerapi"
    var scope = "openid email offline_access"
}
