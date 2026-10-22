import Foundation
import CoreGraphics

enum PetMood: String {
    case calm, curious, happy, relaxed, startled, shy, sleepy, held, settling
}

enum PetSound: CaseIterable {
    case hello, curious, happy, purr, surprised, settled
}

enum PetEffect {
    case sound(PetSound)
    case touch
}

// All times are supplied by the caller, so cooldowns and transitions can be tested.
final class PetBehavior {
    private(set) var reaction: PetMood = .calm
    private(set) var reactionUntil: TimeInterval = 0
    private(set) var lastSeen: TimeInterval = -.infinity
    private(set) var lastInteraction: TimeInterval
    private(set) var faceTarget = CGPoint.zero
    private(set) var isHeld = false
    private var visibleSince: TimeInterval?
    private var greetedThisVisit = false
    private var lastGreeting: TimeInterval = -.infinity
    private var lastPoke: TimeInterval = -.infinity
    private var pokeCount = 0
    private var lastTouchEffect: TimeInterval = -.infinity
    private var lastContact: TimeInterval = -.infinity
    private var effects: [PetEffect] = []
    private var wakeUntil: TimeInterval = 0

    init(now: TimeInterval) { lastInteraction = now }

    func observe(_ box: CGRect?, now: TimeInterval) {
        if let box {
            if mood(now: now) == .sleepy { wakeUntil = now + 0.30 }
            if now - lastSeen > 2 {
                visibleSince = now
                greetedThisVisit = false
            }
            lastSeen = now
            faceTarget = Gaze.target(for: box)
            if !greetedThisVisit, let since = visibleSince, now - since >= 0.7 {
                greetedThisVisit = true
                if now - lastGreeting >= 45 && now - lastContact >= 3 {
                    lastGreeting = now
                    respond(.happy, duration: 1.6, sound: .hello, now: now, tactile: false)
                }
            }
        }
    }

    func mood(now: TimeInterval) -> PetMood {
        if now < wakeUntil { return .curious }
        if now < reactionUntil { return reaction }
        if isHeld { return .held }
        if now - lastSeen > 35 && now - lastInteraction > 35 { return .sleepy }
        return .calm
    }

    func gaze(now: TimeInterval) -> CGPoint {
        if mood(now: now) == .shy {
            return CGPoint(x: -0.65, y: 0.15)
        }
        if now - lastSeen < 2 {
            // Briefly look away during quiet companionship instead of staring continuously.
            if now - lastInteraction > 12 && now.truncatingRemainder(dividingBy: 23) < 2 {
                return CGPoint(x: -0.35, y: 0.10)
            }
            return faceTarget
        }
        if now - lastSeen < 4 { return faceTarget }
        return CGPoint(x: sin(now * 0.40) * 0.23, y: cos(now * 0.27) * 0.10)
    }

    func wake(now: TimeInterval) {
        if mood(now: now) == .sleepy { wakeUntil = now + 0.30 }
        lastInteraction = now
        lastContact = now
    }

    func poke(now: TimeInterval) {
        wake(now: now)
        pokeCount = now - lastPoke < 1.5 ? pokeCount + 1 : 1
        lastPoke = now
        if pokeCount >= 3 {
            respond(.shy, duration: 2.0, sound: .surprised, now: now)
        } else {
            respond(pokeCount == 1 ? .curious : .startled, duration: 1.1,
                    sound: pokeCount == 1 ? .curious : .surprised, now: now)
        }
    }

    func stroke(now: TimeInterval) {
        wake(now: now)
        pokeCount = 0
        respond(.happy, duration: 2.5, sound: .happy, now: now)
    }

    func soothe(now: TimeInterval) {
        wake(now: now)
        pokeCount = 0
        respond(.relaxed, duration: 3.0, sound: .purr, now: now)
    }

    func movement(began: Bool, now: TimeInterval) {
        isHeld = began
        wake(now: now)
        respond(began ? .held : .settling, duration: began ? 1.2 : 2.0,
                sound: began ? .surprised : .settled, now: now, tactile: false)
    }

    func resetPresence(now: TimeInterval) {
        lastSeen = -.infinity
        visibleSince = nil
        greetedThisVisit = false
        isHeld = false
        effects.removeAll()
        lastInteraction = now
        reactionUntil = now
        wakeUntil = now
    }

    func takeEffects() -> [PetEffect] {
        defer { effects.removeAll() }
        return effects
    }

    func express(_ mood: PetMood, now: TimeInterval) {
        guard now - lastContact > 1.2 else { return }
        reaction = mood
        reactionUntil = now + 5
    }

    private func respond(_ mood: PetMood, duration: TimeInterval, sound: PetSound,
                         now: TimeInterval, tactile: Bool = true) {
        reaction = mood
        reactionUntil = now + duration
        if tactile {
            guard now - lastTouchEffect >= 0.8 else { return }
            lastTouchEffect = now
            effects.append(.touch)
        }
        effects.append(.sound(sound))
    }
}

struct PetMotionFilter {
    private var movingSince: TimeInterval?
    private var stillSince: TimeInterval?
    private(set) var moving = false

    mutating func update(acceleration: Double, rotation: Double, now: TimeInterval) -> Bool? {
        if acceleration > 0.16 || rotation > 0.8 {
            stillSince = nil
            if movingSince == nil { movingSince = now }
            if !moving && now - movingSince! >= 0.25 {
                moving = true
                return true
            }
        } else {
            movingSince = nil
            if acceleration < 0.045 && rotation < 0.12 {
                if stillSince == nil { stillSince = now }
                if moving && now - stillSince! >= 1.5 {
                    moving = false
                    return false
                }
            } else { stillSince = nil }
        }
        return nil
    }
}
