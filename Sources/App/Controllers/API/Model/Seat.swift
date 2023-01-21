enum Seat {
    case frontLeft
    case frontRight
    case rearLeft
    case rearCenter
    case rearRight
    
    var heatCoolId: Int {
        switch self {
        case .frontLeft:
            return 0
        case .frontRight:
            return 1
        case .rearLeft:
            return 2
        case .rearCenter:
            return 4
        case .rearRight:
            return 5
        }
    }
    
    var autoId: Int? {
        switch self {
        case .frontLeft:
            return 1
        case .frontRight:
            return 2
        case .rearLeft, .rearCenter, .rearRight:
            return nil
        }
    }
}
