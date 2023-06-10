import Vapor

struct Vehicle: Content, Identifiable {
    
    // MARK: - Public Vars
    
    var id: UInt64
    var vehicleId: UInt64
    
    var vin: String
    
    var state: String
}
