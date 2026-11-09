import Combine
import Foundation
import simd

enum StoryOpponent: String, Codable, CaseIterable, Identifiable, Sendable {
    case basic, pressure, outboxer, counter, southpaw, slugger, rival

    var id: String { rawValue }
    var maximumRounds: Int {
        switch self {
        case .basic: 2
        case .pressure: 4
        case .outboxer: 6
        case .counter: 8
        case .southpaw: 8
        case .slugger: 10
        case .rival: 12
        }
    }
    var isAvailable: Bool { true }
    var hasAppearance: Bool { self != .basic }
}

enum StorySide: String, Codable, Sendable {
    case player, opponent
}

struct StoryIntroduction: Sendable {
    let opponent: StoryOpponent
    let short: Bool
    let duration: Double
    var elapsed: Double = 0

    static func coachDuration(short: Bool) -> Double { short ? 5.6 : 10.0 }

    var coachStartTime: Double { max(0, duration - Self.coachDuration(short: short)) }
    var coachElapsed: Double { max(0, elapsed - coachStartTime) }
    var isCoachBriefing: Bool { elapsed >= coachStartTime }
    var coachAdviceIndex: Int { short || coachElapsed >= 5.0 ? 1 : 0 }
    var transitionOpacity: Double {
        max(0, max(1 - abs(elapsed - coachStartTime) / 0.20,
                   1 - abs(elapsed - (duration - 0.9)) / 0.20))
    }

    var dialogueStartTime: Double {
        switch opponent {
        case .basic: 5.8
        case .outboxer: 4.8
        case .counter: 4.95
        case .southpaw: 5.8
        case .slugger: 6.0
        case .rival: 4.5
        default: 4.3
        }
    }
}

struct StoryRivalScene: Sendable {
    let chapter: StoryOpponent
    let duration: Double
    var elapsed: Double = 0
    var sparringKnockout = false
}

struct StoryIntroVector: Decodable, Sendable {
    let x: Float
    let y: Float
    let z: Float
    var value: SIMD3<Float> { SIMD3<Float>(x, y, z) }
    var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }

    func blended(with other: Self, amount: Float) -> SIMD3<Float> {
        value + (other.value - value) * amount
    }
}

struct StoryIntroPose: Decodable, Sendable {
    let torsoY: Float
    let torsoYaw: Float
    let torsoPitch: Float
    let torsoLean: Float
    let hipYaw: Float
    let headBob: Float
    let leftFootYaw: Float
    let rightFootYaw: Float
    let leftFootPitch: Float
    let rightFootPitch: Float
    let leftShoulder: StoryIntroVector
    let rightShoulder: StoryIntroVector
    let leftElbow: StoryIntroVector
    let rightElbow: StoryIntroVector
    let leftGlove: StoryIntroVector
    let rightGlove: StoryIntroVector
    let leftHip: StoryIntroVector
    let rightHip: StoryIntroVector
    let leftKnee: StoryIntroVector
    let rightKnee: StoryIntroVector
    let leftFoot: StoryIntroVector
    let rightFoot: StoryIntroVector

    var isFinite: Bool {
        [torsoY, torsoYaw, torsoPitch, torsoLean, hipYaw, headBob, leftFootYaw,
         rightFootYaw, leftFootPitch, rightFootPitch].allSatisfy(\.isFinite)
            && [leftShoulder, rightShoulder, leftElbow, rightElbow, leftGlove, rightGlove,
                leftHip, rightHip, leftKnee, rightKnee, leftFoot, rightFoot].allSatisfy(\.isFinite)
    }

    func blended(with other: Self, amount: Float) -> FightPose {
        func scalar(_ start: Float, _ end: Float) -> Float { start + (end - start) * amount }
        var pose = FightPose.neutral(stride: 0)
        pose.torsoY = scalar(torsoY, other.torsoY)
        pose.torsoYaw = scalar(torsoYaw, other.torsoYaw)
        pose.torsoPitch = scalar(torsoPitch, other.torsoPitch)
        pose.torsoLean = scalar(torsoLean, other.torsoLean)
        pose.hipYaw = scalar(hipYaw, other.hipYaw)
        pose.headBob = scalar(headBob, other.headBob)
        pose.leftFootYaw = scalar(leftFootYaw, other.leftFootYaw)
        pose.rightFootYaw = scalar(rightFootYaw, other.rightFootYaw)
        pose.leftFootPitch = scalar(leftFootPitch, other.leftFootPitch)
        pose.rightFootPitch = scalar(rightFootPitch, other.rightFootPitch)
        pose.leftShoulder = leftShoulder.blended(with: other.leftShoulder, amount: amount)
        pose.rightShoulder = rightShoulder.blended(with: other.rightShoulder, amount: amount)
        pose.leftElbow = leftElbow.blended(with: other.leftElbow, amount: amount)
        pose.rightElbow = rightElbow.blended(with: other.rightElbow, amount: amount)
        pose.leftGlove = leftGlove.blended(with: other.leftGlove, amount: amount)
        pose.rightGlove = rightGlove.blended(with: other.rightGlove, amount: amount)
        pose.leftHip = leftHip.blended(with: other.leftHip, amount: amount)
        pose.rightHip = rightHip.blended(with: other.rightHip, amount: amount)
        pose.leftKnee = leftKnee.blended(with: other.leftKnee, amount: amount)
        pose.rightKnee = rightKnee.blended(with: other.rightKnee, amount: amount)
        pose.leftFoot = leftFoot.blended(with: other.leftFoot, amount: amount)
        pose.rightFoot = rightFoot.blended(with: other.rightFoot, amount: amount)
        return pose
    }
}

struct StoryIntroFrame: Decodable, Sendable {
    let time: Double
    let root: StoryIntroVector
    let heading: Float
    let pose: StoryIntroPose
}

struct StoryIntroSample: Sendable {
    let root: SIMD3<Float>
    let heading: Float
    let pose: FightPose
}

enum GymSparringMotion {
    static let introductionDuration = 9.0
    static let aftermathDuration = 6.4
    static let rematchDuration = 4.8

    static func approach(at elapsed: Double) -> Float {
        smooth((elapsed - 2.0) / 1.6) * (1 - smooth((elapsed - 7.5) / 1.5))
    }

    static func introduction(at elapsed: Double, player: Bool = false, walkDistance: Float = 1.0) -> StoryIntroSample {
        let time = min(introductionDuration, max(0, elapsed))
        var pose = greeting(at: time - 4.0)
        if !player, time < 2.0 {
            let adjustment = Float(sin(time / 2.0 * .pi))
            pose.applyGuard(style: .standard, amount: 0.45)
            pose.rightGlove = mix(pose.rightGlove, SIMD3<Float>(-0.16, 1.70, 0.57), adjustment)
            pose.rightElbow = mix(pose.rightElbow, SIMD3<Float>(0.22, 1.52, 0.28), adjustment)
        }
        if !player, time >= 5.8, time <= 6.6 {
            pose.headBob -= Float(sin((time - 5.8) / 0.8 * .pi)) * 0.045
        }
        if time >= 2.0, time < 3.6 {
            applySteps(to: &pose, progress: smooth((time - 2.0) / 1.6), distance: walkDistance)
        } else if time >= 7.5, time < introductionDuration {
            applySteps(to: &pose, progress: smooth((time - 7.5) / 1.5), distance: -walkDistance)
        }
        pose.resolveStraightPunch(leftContact: pose.leftFoot, rightContact: pose.rightFoot)
        return StoryIntroSample(root: .zero, heading: 0, pose: pose)
    }

    static func aftermath(at elapsed: Double, knockout: Bool = false) -> StoryIntroSample {
        let time = min(aftermathDuration, max(0, elapsed))
        var pose = knockout ? FightPose.neutral(stride: 0) : greeting(at: time - 0.55)
        pose.headBob -= Float(sin(min(1, time / 1.2) * .pi)) * 0.05
        if knockout, time < 2.8 {
            pose.torsoPitch += (1 - smooth(time / 2.8)) * 0.10
            pose.applyGuard(style: .standard, amount: 0.20)
        }
        let watching = smooth((time - 2.2) / 0.7) * (1 - smooth((time - 3.4) / 0.6))
        let heading = -watching * 0.25
        if !knockout, let spec = CombatData.attacks[.jab], time >= 4.35, time < 4.35 + spec.duration {
            let target = SIMD3<Float>(0.06, 2.17, Float(spec.range * CombatData.sceneScale) + 0.20)
            pose.applyAttack(.jab, progress: Float((time - 4.35) / spec.duration),
                targetRadius: 0, contactTarget: target)
        }
        pose.resolveStraightPunch(leftContact: pose.leftFoot, rightContact: pose.rightFoot)
        return StoryIntroSample(root: .zero, heading: heading, pose: pose)
    }

    static func departingPlayer(at elapsed: Double) -> StoryIntroSample {
        let time = min(aftermathDuration, max(0, elapsed))
        var pose = greeting(at: time - 0.55)
        let turn = smooth((time - 2.2) / 0.55)
        let departure = smooth((time - 2.75) / 1.05)
        let exitHeading: Float = -2.0
        if time >= 2.2 {
            pose = FightPose.neutral(stride: 0)
            pose.applyGuard(style: .standard, amount: 0.70 * (1 - turn))
            if time < 2.75 {
                applyTurn(to: &pose, progress: turn, angle: exitHeading)
            } else {
                applySteps(to: &pose, progress: departure, distance: 0.65)
            }
        }
        let rotation = simd_quatf(angle: exitHeading, axis: SIMD3<Float>(0, 1, 0))
        return StoryIntroSample(root: rotation.act(SIMD3<Float>(0, 0, departure * 0.65)),
            heading: exitHeading * turn, pose: pose)
    }

    static func rematchApproach(at elapsed: Double) -> Float {
        smooth(elapsed / 1.3) * (1 - smooth((elapsed - 3.2) / 1.6))
    }

    static func rematch(at elapsed: Double, walkDistance: Float = 1.0) -> StoryIntroSample {
        var pose = greeting(at: elapsed - 1.3)
        if elapsed >= 0, elapsed < 1.3 {
            applySteps(to: &pose, progress: smooth(elapsed / 1.3), distance: walkDistance)
        } else if elapsed >= 3.2, elapsed < rematchDuration {
            applySteps(to: &pose, progress: smooth((elapsed - 3.2) / 1.6), distance: -walkDistance)
        }
        return StoryIntroSample(root: .zero, heading: 0, pose: pose)
    }

    private static func applySteps(to pose: inout FightPose, progress: Float, distance: Float) {
        guard abs(distance) > 0.001 else { return }
        let count = max(1, Int((abs(distance) / 0.65).rounded(.up)))
        let cycle = progress * Float(count)
        let completed = cycle.rounded(.down)
        let phase = cycle - completed
        let leftPhase = min(1, max(0, (phase - (distance < 0 ? 0.5 : 0)) * 2))
        let rightPhase = min(1, max(0, (phase - (distance < 0 ? 0 : 0.5)) * 2))
        let stride = distance / Float(count)
        let rootTravel = distance * progress
        let leftTravel = stride * (completed + smooth(Double(leftPhase))) - rootTravel
        let rightTravel = stride * (completed + smooth(Double(rightPhase))) - rootTravel
        let leftLift = max(0, Float(sin(Double(leftPhase) * .pi))) * 0.07
        let rightLift = max(0, Float(sin(Double(rightPhase) * .pi))) * 0.07
        let leftOffset = SIMD3<Float>(0, leftLift, leftTravel)
        let rightOffset = SIMD3<Float>(0, rightLift, rightTravel)
        pose.leftFoot += leftOffset
        pose.rightFoot += rightOffset
        pose.leftKnee += leftOffset * 0.55
        pose.rightKnee += rightOffset * 0.55
        let direction: Float = distance < 0 ? -1 : 1
        pose.leftFootPitch += Float(sin(Double(leftPhase) * .pi * 2)) * direction * 0.10
        pose.rightFootPitch += Float(sin(Double(rightPhase) * .pi * 2)) * direction * 0.10
        pose.headBob -= (leftLift + rightLift) * 0.15
    }

    private static func applyTurn(to pose: inout FightPose, progress: Float, angle: Float) {
        let leftPhase = min(1, progress * 2)
        let rightPhase = max(0, progress * 2 - 1)
        let leftAmount = smooth(Double(leftPhase))
        let rightAmount = smooth(Double(rightPhase))
        let rotation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
        let inverse = simd_quatf(angle: -angle * progress, axis: SIMD3<Float>(0, 1, 0))
        let originalLeft = pose.leftFoot
        let originalRight = pose.rightFoot
        pose.leftFoot = inverse.act(mix(originalLeft, rotation.act(originalLeft), leftAmount))
        pose.rightFoot = inverse.act(mix(originalRight, rotation.act(originalRight), rightAmount))
        pose.leftFoot.y += max(0, Float(sin(Double(leftPhase) * .pi))) * 0.06
        pose.rightFoot.y += max(0, Float(sin(Double(rightPhase) * .pi))) * 0.06
        pose.leftKnee += (pose.leftFoot - originalLeft) * 0.55
        pose.rightKnee += (pose.rightFoot - originalRight) * 0.55
        pose.leftFootYaw += angle * (leftAmount - progress)
        pose.rightFootYaw += angle * (rightAmount - progress)
    }

    private static func greeting(at elapsed: Double) -> FightPose {
        var pose = FightPose.neutral(stride: 0)
        pose.applyGuard(style: .standard, amount: 0.70)
        let amount = smooth(elapsed / 0.55) * (1 - smooth((elapsed - 1.1) / 0.55))
        pose.torsoYaw *= 1 - amount
        pose.leftGlove = mix(pose.leftGlove, SIMD3<Float>(0, 1.75, 1.10), amount)
        pose.leftElbow = mix(pose.leftElbow, SIMD3<Float>(-0.23, 1.72, 0.56), amount)
        return pose
    }

    private static func smooth(_ value: Double) -> Float {
        let amount = Float(min(1, max(0, value)))
        return amount * amount * (3 - 2 * amount)
    }

    private static func mix(_ start: SIMD3<Float>, _ end: SIMD3<Float>, _ amount: Float) -> SIMD3<Float> {
        start + (end - start) * amount
    }
}

private extension StoryIntroPose {
    init(_ pose: FightPose) {
        func vector(_ value: SIMD3<Float>) -> StoryIntroVector {
            StoryIntroVector(x: value.x, y: value.y, z: value.z)
        }
        self.init(torsoY: pose.torsoY, torsoYaw: pose.torsoYaw, torsoPitch: pose.torsoPitch,
            torsoLean: pose.torsoLean, hipYaw: pose.hipYaw, headBob: pose.headBob,
            leftFootYaw: pose.leftFootYaw, rightFootYaw: pose.rightFootYaw,
            leftFootPitch: pose.leftFootPitch, rightFootPitch: pose.rightFootPitch,
            leftShoulder: vector(pose.leftShoulder), rightShoulder: vector(pose.rightShoulder),
            leftElbow: vector(pose.leftElbow), rightElbow: vector(pose.rightElbow),
            leftGlove: vector(pose.leftGlove), rightGlove: vector(pose.rightGlove),
            leftHip: vector(pose.leftHip), rightHip: vector(pose.rightHip),
            leftKnee: vector(pose.leftKnee), rightKnee: vector(pose.rightKnee),
            leftFoot: vector(pose.leftFoot), rightFoot: vector(pose.rightFoot))
    }
}

enum ChampionshipEndingTiming {
    static let applauseOpponents: [StoryOpponent] = [.pressure, .outboxer, .counter, .southpaw, .slugger, .rival]
    static let beltAward = 6.8
    static let ceremonyStart = 8.0
    static let coachCongratulations = 11.4
    static let coachApplausePeriod = 0.76
    static let gymCut = 16.0
    static let shadowboxingDuration = 6.4
    static let duration = gymCut + shadowboxingDuration

    static func applausePeriod(for index: Int) -> Double { 0.58 + Double(index) * 0.022 }
    static func applauseOffset(for index: Int) -> Double { Double(index) * 0.11 }
}

enum ChampionshipShadowboxingMotion {
    static let punches: [(start: Double, punch: Punch)] = [
        (0.45, .jab), (0.70, .cross), (1.10, .leftHook),
        (2.10, .rightBody), (2.50, .leftUppercut), (2.96, .cross),
        (4.32, .jab), (4.60, .rightUppercut), (5.10, .leftHook)
    ]

    static func sample(at elapsed: Double) -> StoryIntroSample {
        let time = min(ChampionshipEndingTiming.shadowboxingDuration, max(0, elapsed.isFinite ? elapsed : 0))
        var pose = FightPose.neutral(stride: 0, style: .standard)
        pose.applyGuard(style: .standard, amount: 0.35)
        pose.headBob = Float(sin(time * 2.4)) * 0.005
        if time >= 1.64, time < 2.03 {
            let slip = Float(sin((time - 1.64) / 0.39 * .pi)) * 0.55
            pose.applyDuck(direction: -slip, style: .standard)
        }
        if time >= 3.45, time < 4.06 {
            let step = Float(sin((time - 3.45) / 0.61 * .pi))
            pose.applyFootwork(forward: -0.30, strafe: 0.50, strideCycle: step)
        }
        for beat in punches {
            guard let spec = CombatData.attacks[beat.punch],
                  time >= beat.start, time < beat.start + spec.duration else { continue }
            let lead = [.jab, .leftBody, .leftHook, .leftUppercut].contains(beat.punch)
            let reach = Float(spec.range * CombatData.sceneScale) + (spec.family == .straight ? 0.20 : 0.12)
            let target = SIMD3<Float>(lead ? 0.06 : -0.06, spec.targetZone == .body ? 1.35 : 2.17, reach)
            pose.applyAttack(beat.punch, progress: Float((time - beat.start) / spec.duration),
                targetRadius: 0, contactTarget: target)
            break
        }
        pose.resolveStraightPunch(leftContact: pose.leftFoot, rightContact: pose.rightFoot)
        return StoryIntroSample(root: .zero, heading: 0, pose: pose)
    }
}

struct StoryIntroClip: Decodable, Sendable {
    let version: Int
    let duration: Double
    let frames: [StoryIntroFrame]
    var southpawAftermath: Bool? = nil

    @MainActor static let basic = sparringClip(aftermath: false)
    @MainActor static let basicAftermath = sparringClip(aftermath: true)
    @MainActor static let southpaw = southpawClip(aftermath: false)
    @MainActor static let rivalSouthpawWin = southpawClip(aftermath: true)
    @MainActor static let pressure = load(resource: "story_pressure_intro")
    @MainActor static let outboxer = load(resource: "story_outboxer_intro")
    @MainActor static let counter = load(resource: "story_counter_intro")
    @MainActor static let slugger = load(resource: "story_slugger_intro")
    @MainActor static let championship = load(resource: "story_championship_intro")
    @MainActor static let championshipEnding = load(resource: "story_championship_ending")
    @MainActor static let championshipEndingPlayer = load(resource: "story_championship_ending_player")
    @MainActor static let rivalPressureWin = load(resource: "story_rival_pressure_win")
    @MainActor static let rivalOutboxerWin = load(resource: "story_rival_outboxer_win")
    @MainActor static let rivalCounterWin = load(resource: "story_rival_counter_win")
    @MainActor static let rivalSluggerWin = load(resource: "story_rival_slugger_win")

    @MainActor static func rivalScene(for opponent: StoryOpponent) -> StoryIntroClip? {
        switch opponent {
        case .basic: basicAftermath
        case .southpaw: rivalSouthpawWin
        case .pressure: rivalPressureWin
        case .outboxer: rivalOutboxerWin
        case .counter: rivalCounterWin
        case .slugger: rivalSluggerWin
        case .rival: championshipEndingPlayer == nil ? nil : championshipEnding
        }
    }

    @MainActor static func clip(for opponent: StoryOpponent?) -> StoryIntroClip? {
        switch opponent {
        case .basic: basic
        case .pressure: pressure
        case .outboxer: outboxer
        case .counter: counter
        case .southpaw: southpaw
        case .slugger: slugger
        case .rival: championship
        default: nil
        }
    }

    private static func southpawClip(aftermath: Bool) -> StoryIntroClip {
        let duration = aftermath ? 8.0 : 9.0
        let count = Int(duration * 60)
        let frames = (0...count).map { index in
            let time = duration * Double(index) / Double(count)
            let stance: BoxingStance = !aftermath || (time >= 2 && time < 4) ? .southpaw : .orthodox
            var pose = FightPose.neutral(stride: 0, stance: stance)
            pose.applyGuard(style: .standard, amount: 0.70)
            let attacks: [(Punch, Double)] = aftermath ? [(.jab, 6.1)] : [(.jab, 2.4), (.cross, 3.15)]
            for (punch, start) in attacks {
                guard let spec = CombatData.attacks[punch], time >= start, time < start + spec.duration else { continue }
                let progress = Float((time - start) / spec.duration)
                pose.applyAttack(punch, progress: progress)
                pose.applyPunchRecovery(punch, progress: progress, landed: false, reducedMotion: false)
            }
            let stepStart = aftermath ? 4.7 : 5.0
            let step = Float(min(1, max(0, (time - stepStart) / 0.65)))
            let travel: Float = 0.30 * (step * step * (3 - 2 * step))
            pose.leftFoot.x -= travel
            pose.rightFoot.x -= travel
            if step > 0, step < 0.5 {
                pose.rightFoot.x += travel * 2
                pose.rightFoot.y += sin(step * 2 * .pi) * 0.045
            } else if step >= 0.5, step < 1 {
                pose.rightFoot.x += 0.30
                pose.leftFoot.x += (travel - 0.15) * 2
                pose.leftFoot.y += sin((step - 0.5) * 2 * .pi) * 0.045
            } else if step >= 1 {
                pose.leftFoot.x += 0.30
                pose.rightFoot.x += 0.30
            }
            return StoryIntroFrame(time: time, root: StoryIntroVector(x: travel, y: 0, z: 0),
                heading: 0, pose: StoryIntroPose(pose))
        }
        return StoryIntroClip(version: 1, duration: duration, frames: frames, southpawAftermath: aftermath)
    }

    private static func sparringClip(aftermath: Bool) -> StoryIntroClip {
        let duration = aftermath ? GymSparringMotion.aftermathDuration : GymSparringMotion.introductionDuration
        let count = Int(duration * 60)
        let frames = (0...count).map { index in
            let time = duration * Double(index) / Double(count)
            let sample = aftermath ? GymSparringMotion.aftermath(at: time) : GymSparringMotion.introduction(at: time)
            return StoryIntroFrame(time: time,
                root: StoryIntroVector(x: sample.root.x, y: sample.root.y, z: sample.root.z),
                heading: sample.heading, pose: StoryIntroPose(sample.pose))
        }
        return StoryIntroClip(version: 1, duration: duration, frames: frames)
    }

    @MainActor private static func load(resource: String) -> StoryIntroClip? {
        let url = Bundle.main.url(forResource: resource, withExtension: "json")
            ?? Bundle.main.url(forResource: resource, withExtension: "json", subdirectory: "Resources")
        guard let url, let data = try? Data(contentsOf: url),
              let clip = try? JSONDecoder().decode(StoryIntroClip.self, from: data),
              clip.version == 1, clip.duration.isFinite, clip.duration > 0, clip.duration <= 30,
              (2...10_000).contains(clip.frames.count),
              clip.frames.first?.time == 0, clip.frames.last?.time == clip.duration,
              clip.frames.allSatisfy({ $0.time.isFinite && $0.root.isFinite && $0.heading.isFinite && $0.pose.isFinite }),
              zip(clip.frames, clip.frames.dropFirst()).allSatisfy({ $0.time < $1.time }) else { return nil }
        return clip
    }

    func sample(at elapsed: Double) -> StoryIntroSample {
        let time = min(duration, max(0, elapsed.isFinite ? elapsed : 0))
        var lower = 0
        var upper = frames.count - 1
        while upper - lower > 1 {
            let middle = (lower + upper) / 2
            if frames[middle].time <= time { lower = middle } else { upper = middle }
        }
        let first = frames[lower]
        let second = frames[upper]
        let amount = Float(min(1, max(0, (time - first.time) / (second.time - first.time))))
        var pose = first.pose.blended(with: second.pose, amount: amount)
        if let aftermath = southpawAftermath {
            pose.setAuthoredStance(!aftermath || (time >= 2 && time < 4) ? .southpaw : .orthodox)
        }
        return StoryIntroSample(root: first.root.blended(with: second.root, amount: amount),
            heading: first.heading + (second.heading - first.heading) * amount,
            pose: pose)
    }
}

enum StoryBoutPhase: String, Codable, Sendable {
    case fighting, counting, corner, finished
}

enum StoryVerdict: String, Codable, Sendable {
    case win, loss, draw
}

enum StoryFinish: String, Codable, Sendable {
    case decision, technicalKnockout
}

struct StoryRules: Codable, Equatable, Sendable {
    var roundSeconds: Double = 60
    var maximumDownsPerRound: Int = 3
    var getupHealth: Int = 60
    var getupStamina: Double = 50
    var minimumCount: Int = 4
    var maximumCount: Int = 9
    var damagePerCount: Int = 8
    var cornerSeconds: Double = 4
    var evenRoundMargin: Double = 6

    func count(forResolvedDamage damage: Int) -> Int {
        min(maximumCount, max(minimumCount, minimumCount + max(0, damage) / max(1, damagePerCount)))
    }
}

struct StoryRoundStats: Codable, Equatable, Sendable {
    var playerDamage = 0
    var opponentDamage = 0
    var playerCleanHits = 0
    var opponentCleanHits = 0
    var playerCounters = 0
    var opponentCounters = 0
    var playerDowns = 0
    var opponentDowns = 0

    var performanceDifference: Double {
        Double(playerDamage - opponentDamage)
            + Double(playerCleanHits - opponentCleanHits) * 2
            + Double(playerCounters - opponentCounters) * 3
    }
}

struct StoryRoundCard: Codable, Equatable, Identifiable, Sendable {
    let round: Int
    let playerPoints: Int
    let opponentPoints: Int
    let stats: StoryRoundStats
    var id: Int { round }
}

struct StoryRoundTransition: Equatable, Sendable {
    static let fadeOutDuration = 0.18
    static let resetTime = 0.28
    static let fadeInStart = 0.46
    static let duration = 0.88

    let round: Int
    var elapsed = 0.0

    var opacity: Double {
        if elapsed < Self.fadeOutDuration {
            let progress = max(0, elapsed / Self.fadeOutDuration)
            return progress * progress * (3 - 2 * progress)
        }
        let progress = min(1, max(0, (elapsed - Self.fadeInStart) / (Self.duration - Self.fadeInStart)))
        return 1 - progress * progress * (3 - 2 * progress)
    }

    var titleOpacity: Double {
        let progress = min(1, max(0, (elapsed - Self.resetTime) / 0.12))
        return progress * progress * (3 - 2 * progress)
    }
}

struct StoryBoutState: Codable, Equatable, Sendable {
    let opponent: StoryOpponent
    var rules = StoryRules()
    private(set) var round = 1
    private(set) var phase = StoryBoutPhase.fighting
    private(set) var stats = StoryRoundStats()
    private(set) var cards: [StoryRoundCard] = []
    private(set) var countingSide: StorySide?
    private(set) var getupCount = 0
    private(set) var countElapsed: Double = 0
    private(set) var cornerElapsed: Double = 0
    private(set) var verdict: StoryVerdict?
    private(set) var finish: StoryFinish?

    var playerPoints: Int { cards.reduce(0) { $0 + $1.playerPoints } }
    var opponentPoints: Int { cards.reduce(0) { $0 + $1.opponentPoints } }
    var displayedCount: Int { min(getupCount, max(1, Int(countElapsed) + 1)) }
    var getupProgress: Double {
        guard phase == .counting else { return 0 }
        let duration = 0.7
        return min(1, max(0, (countElapsed - Double(getupCount) + duration) / duration))
    }
    var getupKnockdownAmount: Double {
        let progress = getupProgress
        return 1 - progress * progress * (3 - 2 * progress)
    }
    var canStartNextRound: Bool { phase == .corner && cornerElapsed >= rules.cornerSeconds }
    var advantage: Int {
        let completedDifference = playerPoints - opponentPoints
        if completedDifference != 0 { return completedDifference > 0 ? 1 : -1 }
        if abs(stats.performanceDifference) <= rules.evenRoundMargin { return 0 }
        return stats.performanceDifference > 0 ? 1 : -1
    }

    mutating func recordImpact(by side: StorySide, damage: Int, guarded: Bool, counter: Bool) {
        guard phase == .fighting else { return }
        if side == .player {
            stats.playerDamage += max(0, damage)
            if !guarded { stats.playerCleanHits += 1 }
            if counter { stats.playerCounters += 1 }
        } else {
            stats.opponentDamage += max(0, damage)
            if !guarded { stats.opponentCleanHits += 1 }
            if counter { stats.opponentCounters += 1 }
        }
    }

    mutating func knockdown(_ side: StorySide, resolvedDamage: Int) {
        guard phase == .fighting else { return }
        if side == .player { stats.playerDowns += 1 } else { stats.opponentDowns += 1 }
        let downs = side == .player ? stats.playerDowns : stats.opponentDowns
        if downs >= rules.maximumDownsPerRound {
            appendRoundCard()
            verdict = side == .player ? .loss : .win
            finish = .technicalKnockout
            phase = .finished
            countingSide = nil
        } else {
            countingSide = side
            getupCount = rules.count(forResolvedDamage: resolvedDamage)
            countElapsed = 0
            phase = .counting
        }
    }

    mutating func advanceCount(_ deltaTime: Double) -> Bool {
        guard phase == .counting, deltaTime.isFinite, deltaTime > 0 else { return false }
        countElapsed += deltaTime
        guard countElapsed >= Double(getupCount) else { return false }
        phase = .fighting
        countingSide = nil
        return true
    }

    mutating func advanceCorner(_ deltaTime: Double) {
        guard phase == .corner, deltaTime.isFinite, deltaTime > 0 else { return }
        cornerElapsed = min(rules.cornerSeconds, cornerElapsed + deltaTime)
    }

    mutating func finishRound() {
        guard phase == .fighting else { return }
        appendRoundCard()
        if round >= opponent.maximumRounds {
            verdict = playerPoints == opponentPoints ? .draw : (playerPoints > opponentPoints ? .win : .loss)
            finish = .decision
            phase = .finished
        } else {
            cornerElapsed = 0
            phase = .corner
        }
    }

    mutating func beginNextRound() {
        guard canStartNextRound else { return }
        round += 1
        stats = StoryRoundStats()
        countingSide = nil
        getupCount = 0
        countElapsed = 0
        cornerElapsed = 0
        phase = .fighting
    }

    private mutating func appendRoundCard() {
        guard !cards.contains(where: { $0.round == round }) else { return }
        let difference = stats.performanceDifference
        let playerBase = difference < -rules.evenRoundMargin ? 9 : 10
        let opponentBase = difference > rules.evenRoundMargin ? 9 : 10
        cards.append(StoryRoundCard(round: round,
            playerPoints: max(6, playerBase - stats.playerDowns),
            opponentPoints: max(6, opponentBase - stats.opponentDowns), stats: stats))
    }
}

struct StoryFighterCheckpoint: Codable, Sendable {
    var health: Int
    var stamina: Double
    var positionX: Double
    var positionY: Double
    var facingX: Double
    var facingY: Double
    var exhausted: Double
    var stagger: Double
    var exposed: Double
    var invulnerable: Double = 0
    var repeatedPunch: String?
    var repetitionCount = 0
    var stance = BoxingStance.orthodox
}

struct StoryLearningState: Codable, Sendable {
    var habits = HabitMemory()
    var playerAttacks = RivalAttackMemory()
    var opponentAttacks = RivalAttackMemory()
    var completedRounds = 0
    var championshipRounds = 0

    init() {}

    private enum CodingKeys: String, CodingKey {
        case habits, playerAttacks, opponentAttacks, completedRounds, championshipRounds
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        habits = try values.decodeIfPresent(HabitMemory.self, forKey: .habits) ?? HabitMemory()
        playerAttacks = try values.decodeIfPresent(RivalAttackMemory.self, forKey: .playerAttacks) ?? RivalAttackMemory()
        opponentAttacks = try values.decodeIfPresent(RivalAttackMemory.self, forKey: .opponentAttacks) ?? RivalAttackMemory()
        completedRounds = max(0, try values.decodeIfPresent(Int.self, forKey: .completedRounds) ?? 0)
        championshipRounds = max(0, try values.decodeIfPresent(Int.self, forKey: .championshipRounds) ?? 0)
    }
}

struct StoryRoundObservations: Codable, Sendable {
    var habits = HabitMemory()
    var playerAttacks = RivalAttackMemory()
    var opponentAttacks = RivalAttackMemory()
    var committed = false
    var policyRound = 30

    init() {}

    private enum CodingKeys: String, CodingKey {
        case habits, playerAttacks, opponentAttacks, committed, policyRound
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        habits = try values.decodeIfPresent(HabitMemory.self, forKey: .habits) ?? HabitMemory()
        playerAttacks = try values.decodeIfPresent(RivalAttackMemory.self, forKey: .playerAttacks) ?? RivalAttackMemory()
        opponentAttacks = try values.decodeIfPresent(RivalAttackMemory.self, forKey: .opponentAttacks) ?? RivalAttackMemory()
        committed = try values.decodeIfPresent(Bool.self, forKey: .committed) ?? false
        policyRound = min(230, max(1, try values.decodeIfPresent(Int.self, forKey: .policyRound) ?? 30))
    }
}

struct StoryCheckpoint: Codable, Sendable {
    var bout: StoryBoutState
    var remainingTime: Double
    var player: StoryFighterCheckpoint
    var opponent: StoryFighterCheckpoint
    var playerStyle: String
    var counterWindow: Double = 0
    var lastDodgeGrade: String?
    var focusTime: Double = 0
    var focusGrade: String?
    var learning: StoryLearningState?
    var observations: StoryRoundObservations?
    var rivalStaminaRecovering = false
}

extension StoryFighterCheckpoint {
    private enum CodingKeys: String, CodingKey {
        case health, stamina, positionX, positionY, facingX, facingY, exhausted, stagger, exposed
        case invulnerable, repeatedPunch, repetitionCount
        case stance
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        health = try values.decode(Int.self, forKey: .health)
        stamina = try values.decode(Double.self, forKey: .stamina)
        positionX = try values.decode(Double.self, forKey: .positionX)
        positionY = try values.decode(Double.self, forKey: .positionY)
        facingX = try values.decode(Double.self, forKey: .facingX)
        facingY = try values.decode(Double.self, forKey: .facingY)
        exhausted = try values.decode(Double.self, forKey: .exhausted)
        stagger = try values.decode(Double.self, forKey: .stagger)
        exposed = try values.decode(Double.self, forKey: .exposed)
        invulnerable = try values.decodeIfPresent(Double.self, forKey: .invulnerable) ?? 0
        repeatedPunch = try values.decodeIfPresent(String.self, forKey: .repeatedPunch)
        repetitionCount = try values.decodeIfPresent(Int.self, forKey: .repetitionCount) ?? 0
        stance = try values.decodeIfPresent(BoxingStance.self, forKey: .stance) ?? .orthodox
    }
}

extension StoryCheckpoint {
    private enum CodingKeys: String, CodingKey {
        case bout, remainingTime, player, opponent, playerStyle, counterWindow, lastDodgeGrade, focusTime, focusGrade
        case learning, observations, rivalStaminaRecovering
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bout = try values.decode(StoryBoutState.self, forKey: .bout)
        remainingTime = try values.decode(Double.self, forKey: .remainingTime)
        player = try values.decode(StoryFighterCheckpoint.self, forKey: .player)
        opponent = try values.decode(StoryFighterCheckpoint.self, forKey: .opponent)
        playerStyle = try values.decode(String.self, forKey: .playerStyle)
        counterWindow = try values.decodeIfPresent(Double.self, forKey: .counterWindow) ?? 0
        lastDodgeGrade = try values.decodeIfPresent(String.self, forKey: .lastDodgeGrade)
        focusTime = try values.decodeIfPresent(Double.self, forKey: .focusTime) ?? 0
        focusGrade = try values.decodeIfPresent(String.self, forKey: .focusGrade)
        learning = try values.decodeIfPresent(StoryLearningState.self, forKey: .learning)
        observations = try values.decodeIfPresent(StoryRoundObservations.self, forKey: .observations)
        rivalStaminaRecovering = try values.decodeIfPresent(Bool.self, forKey: .rivalStaminaRecovering)
            ?? (opponent.stamina < 25 || opponent.exhausted > 0)
    }
}

struct StoryProgress: Codable, Sendable {
    var version = 3
    var clearedOpponents: Set<StoryOpponent> = []
    var retainedUnlocks: Set<StoryOpponent> = []
    var legacyRivalUnlocked = false
    var championOutfitUnlocked = false
    var championBeltUnlocked = false
    var championBeltEquipped = false
    var equippedAppearance: StoryOpponent?
    var equippedStance = BoxingStance.orthodox
    var seenIntroductions: Set<StoryOpponent> = []
    var seenRivalScenes: Set<StoryOpponent> = []
    var activeBout: StoryCheckpoint?
    var lastResult: StoryBoutState?
    var learning = StoryLearningState()

    #if DEBUG
    static let temporarilyUnlockStory = true
    #else
    static let temporarilyUnlockStory = false
    #endif

    static var temporarilyUnlockCutscenes: Bool { temporarilyUnlockStory }
    static var temporarilyUnlockEquipment: Bool {
        // Isolated menu fixtures exercise real equipment gates, not the developer unlock.
        temporarilyUnlockStory && ProcessInfo.processInfo.environment["RIVAL_PRESENTATION_TEST"] != "menu"
    }

    func canReplayIntroduction(_ opponent: StoryOpponent) -> Bool {
        opponent.isAvailable && (Self.temporarilyUnlockCutscenes || seenIntroductions.contains(opponent))
    }

    func canReplayRivalScene(_ opponent: StoryOpponent) -> Bool {
        opponent.isAvailable && (Self.temporarilyUnlockCutscenes || clearedOpponents.contains(opponent))
    }

    var rivalUnlocked: Bool {
        legacyRivalUnlocked || retainedUnlocks.contains(.rival) || clearedOpponents.contains(.rival)
            || StoryOpponent.allCases.filter { $0.isAvailable && $0 != .rival }.allSatisfy(clearedOpponents.contains)
    }

    var nextOpponent: StoryOpponent {
        if let opponent = activeBout?.bout.opponent, opponent.isAvailable { return opponent }
        if let opponent = StoryOpponent.allCases.first(where: {
            $0.isAvailable && retainedUnlocks.contains($0) && !clearedOpponents.contains($0)
        }) { return opponent }
        return StoryOpponent.allCases.first(where: {
            $0.isAvailable && isUnlocked($0) && !clearedOpponents.contains($0)
        }) ?? .basic
    }

    func isUnlocked(_ opponent: StoryOpponent) -> Bool {
        guard opponent.isAvailable else { return false }
        #if DEBUG
        if Self.temporarilyUnlockStory { return true }
        #endif
        if opponent == .rival { return rivalUnlocked }
        if retainedUnlocks.contains(opponent) || clearedOpponents.contains(opponent)
            || activeBout?.bout.opponent == opponent { return true }
        guard let index = StoryOpponent.allCases.firstIndex(of: opponent) else { return false }
        return StoryOpponent.allCases.prefix(index).filter(\.isAvailable).allSatisfy(clearedOpponents.contains)
    }

    func canEquipAppearance(_ opponent: StoryOpponent?) -> Bool {
        guard let opponent else { return true }
        return opponent.isAvailable && opponent.hasAppearance
            && (Self.temporarilyUnlockEquipment || clearedOpponents.contains(opponent))
    }

    func canEquipStance(_ stance: BoxingStance) -> Bool {
        stance == .orthodox || (StoryOpponent.southpaw.isAvailable
            && (Self.temporarilyUnlockEquipment || clearedOpponents.contains(.southpaw)))
    }

    private enum CodingKeys: String, CodingKey {
        case version, clearedOpponents, legacyRivalUnlocked, championOutfitUnlocked, championBeltUnlocked
        case championBeltEquipped
        case equippedAppearance, seenIntroductions, seenRivalScenes, activeBout, lastResult
        case learning
        case retainedUnlocks
        case equippedStance
    }

    init(legacyRivalUnlocked: Bool = false) {
        self.legacyRivalUnlocked = legacyRivalUnlocked
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        clearedOpponents = try values.decodeIfPresent(Set<StoryOpponent>.self, forKey: .clearedOpponents) ?? []
        retainedUnlocks = try values.decodeIfPresent(Set<StoryOpponent>.self, forKey: .retainedUnlocks) ?? []
        legacyRivalUnlocked = try values.decodeIfPresent(Bool.self, forKey: .legacyRivalUnlocked) ?? false
        championOutfitUnlocked = try values.decodeIfPresent(Bool.self, forKey: .championOutfitUnlocked) ?? false
        championBeltUnlocked = try values.decodeIfPresent(Bool.self, forKey: .championBeltUnlocked) ?? false
        championBeltEquipped = try values.decodeIfPresent(Bool.self, forKey: .championBeltEquipped) ?? false
        equippedAppearance = try values.decodeIfPresent(StoryOpponent.self, forKey: .equippedAppearance)
        equippedStance = try values.decodeIfPresent(BoxingStance.self, forKey: .equippedStance) ?? .orthodox
        seenIntroductions = try values.decodeIfPresent(Set<StoryOpponent>.self, forKey: .seenIntroductions) ?? clearedOpponents
        seenRivalScenes = try values.decodeIfPresent(Set<StoryOpponent>.self, forKey: .seenRivalScenes) ?? []
        activeBout = try values.decodeIfPresent(StoryCheckpoint.self, forKey: .activeBout)
        lastResult = try values.decodeIfPresent(StoryBoutState.self, forKey: .lastResult)
        learning = try values.decodeIfPresent(StoryLearningState.self, forKey: .learning) ?? StoryLearningState()
        if version < 2 {
            let oldOrder: [StoryOpponent] = [.pressure, .outboxer, .counter, .slugger, .rival]
            if !clearedOpponents.isEmpty || !seenIntroductions.isEmpty || activeBout != nil || lastResult != nil {
                for (index, opponent) in oldOrder.enumerated()
                    where oldOrder.prefix(index).allSatisfy(clearedOpponents.contains) {
                    retainedUnlocks.insert(opponent)
                }
            }
            retainedUnlocks.formUnion(clearedOpponents)
            if let opponent = activeBout?.bout.opponent { retainedUnlocks.insert(opponent) }
            if legacyRivalUnlocked || championOutfitUnlocked || championBeltUnlocked {
                retainedUnlocks.insert(.rival)
            }
            version = 2
        }
        if version < 3 {
            let oldOrder: [StoryOpponent] = [.basic, .pressure, .outboxer, .counter, .slugger, .rival]
            if !clearedOpponents.isEmpty || !seenIntroductions.isEmpty || activeBout != nil || lastResult != nil {
                for (index, opponent) in oldOrder.enumerated()
                    where oldOrder.prefix(index).allSatisfy(clearedOpponents.contains) {
                    retainedUnlocks.insert(opponent)
                }
            }
            retainedUnlocks.formUnion(clearedOpponents)
            if let opponent = activeBout?.bout.opponent { retainedUnlocks.insert(opponent) }
            version = 3
        }
    }
}

@MainActor
final class StoryProgressStore: ObservableObject {
    static let defaultsKey = "rival.story.progress.v1"
    @Published private(set) var progress: StoryProgress
    private let defaults: UserDefaults?
    var persistsProgress: Bool { defaults != nil }

    #if DEBUG
    static func developerPreview(defaults: UserDefaults? = UserDefaults(suiteName: "rival.story.preview.v1")) -> StoryProgressStore {
        // Developer access unlocks content, not the player's equipment selection.
        StoryProgressStore(defaults: defaults)
    }
    #endif

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(StoryProgress.self, from: data) {
            progress = saved
        } else {
            let legacyKeys = ["pixelBoxingHabitMemory", "pixelBoxingRivalResults", "pixelBoxingRound",
                "pixelBoxingHighestRound", "pixelBoxingPlayerScore", "pixelBoxingEnemyScore",
                "pixelBoxingPlayerStyle", "pixelBoxingEquippedOutfit", "pixelBoxingPlayerStats",
                "pixelBoxingSoundMuted", "pixelBoxingHapticsEnabled", "pixelBoxingLanguage"]
            progress = StoryProgress(legacyRivalUnlocked: defaults == nil || legacyKeys.contains { defaults?.object(forKey: $0) != nil })
        }
        persist()
    }

    func save(_ checkpoint: StoryCheckpoint) {
        if let learning = checkpoint.learning { progress.learning = learning }
        if checkpoint.bout.phase == .finished {
            progress.lastResult = checkpoint.bout
            progress.activeBout = nil
            if checkpoint.bout.verdict == .win {
                progress.clearedOpponents.insert(checkpoint.bout.opponent)
                if checkpoint.bout.opponent == .rival {
                    progress.championOutfitUnlocked = true
                    progress.championBeltUnlocked = true
                }
            }
        } else {
            progress.activeBout = checkpoint
        }
        persist()
    }

    func equipAppearance(_ opponent: StoryOpponent?) {
        guard progress.canEquipAppearance(opponent) else { return }
        progress.equippedAppearance = opponent
        persist()
    }

    func equipStance(_ stance: BoxingStance) {
        guard progress.canEquipStance(stance) else { return }
        progress.equippedStance = stance
        persist()
    }

    func equipChampionBelt(_ equipped: Bool) {
        guard !equipped || StoryProgress.temporarilyUnlockEquipment || progress.championBeltUnlocked else { return }
        progress.championBeltEquipped = equipped
        persist()
    }

    func markIntroductionSeen(_ opponent: StoryOpponent) {
        guard progress.seenIntroductions.insert(opponent).inserted else { return }
        persist()
    }

    func markRivalSceneSeen(_ chapter: StoryOpponent) {
        guard progress.seenRivalScenes.insert(chapter).inserted else { return }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        defaults?.set(data, forKey: Self.defaultsKey)
    }
}