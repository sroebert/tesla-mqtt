import Vapor

struct Token: Content {
    
    // MARK: - Public Vars
    
    var accessToken: String
    var tokenType: String
    var expiresIn: Int
    var refreshToken: String
}
