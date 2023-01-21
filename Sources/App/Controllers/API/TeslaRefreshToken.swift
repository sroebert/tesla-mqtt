import Vapor

typealias TeslaRefreshToken = String

extension Application {
    private struct TeslaRefreshTokenStorageKey: StorageKey {
        typealias Value = TeslaRefreshToken
    }
    
    var teslaRefreshToken: TeslaRefreshToken {
        get {
            guard let client = storage[TeslaRefreshTokenStorageKey.self] else {
                fatalError("TeslaRefreshToken is not setup")
            }
            return client
        }
        set {
            storage[TeslaRefreshTokenStorageKey.self] = newValue
        }
    }
}
