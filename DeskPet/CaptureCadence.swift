enum CaptureCadence {
    static func framesPerSecond(thermal: Int) -> Int {
        switch thermal {
        case 0, 1: return 15
        case 2: return 10
        default: return 5
        }
    }
}
