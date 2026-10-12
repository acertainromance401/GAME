/*
 PracticeController.swift

 파일 설명:
 - 연습 모드(Practice)에서 UI와 `PracticeEngine`/`PracticeScene`을 중재하는 컨트롤러입니다.
 - 입력(버튼/터치/가상 패드)을 엔진에 전달하고, 주기적으로 상태를 게시(publish)해 UI를 갱신합니다.

 사용 영향 및 주의사항:
 - 이 컨트롤러 변경은 연습 모드의 입력/피드백 루프에 영향을 줍니다.
 - 주석 추가만으로 동작에는 영향이 없습니다.
*/
import SwiftUI

/// Drives the practice room screen: owns a `PracticeEngine` (no opponent, no round/score) plus the
/// `PracticeScene` that renders it, and composes the same held-button input pattern `GameController` uses
/// for the real fight (a `Set` of held directional controls combined every frame into one move vector).
@MainActor
final class PracticeController: ObservableObject {
    private struct MovementControl: Hashable {
        let forward: Int
        let strafe: Int
    }

    let engine = PracticeEngine()
    let sound = SoundManager()
    @Published private(set) var playerLocked = false
    private var heldMovement: Set<MovementControl> = []
    @Published private(set) var modifiers = CombatModifiers()
    private var heldWeaves: Set<Int> = []
    private var guardHeld: Bool { modifiers.guarding }
    private var duckDirectionHeld: Int { modifiers.duckDirection }

    lazy var scene3D: PracticeScene = {
        let scene = PracticeScene(engine: engine)
        scene.controller = self
        return scene
    }()

    init(style: FightStyle) {
        engine.setStyle(style)
        // The Gym shares the same persisted mute preference as the fight, not an always-on audio path.
        sound.isMuted = UserDefaults.standard.bool(forKey: "pixelBoxingSoundMuted")
        engine.onPunchSwing = { [weak self] punch in
            self?.sound.playPunchSwing(punch)
        }
    }

    func move(x: Double, y: Double, active: Bool) {
        // 이동 입력 처리
        // 상세 동작:
        // - `x`/`y`는 단일 버튼 입력에서 전달되는 정수 값(예: 좌/우/상/하)을 기대합니다.
        // - 여러 방향 버튼이 동시에 눌릴 수 있으므로 각 입력을 `heldMovement` 집합에 추가/제거합니다.
        // - 매 update 루프에서 이 집합을 합산하여 최종 이동 벡터를 계산하고 `PracticeEngine`에 전달합니다.
        // 부작용 및 가시적 영향:
        // - 이 메서드는 즉시 엔진의 목표 이동값을 갱신합니다. UI(씬)에서는 다음 프레임에 해당 값이 반영되어
        //   복서의 위치/애니메이션이 바뀝니다.
        // 성능 및 스레딩:
        // - 이 함수는 빈번하게 호출될 수 있으므로(터치 지속, 가상 패드 반복) 가벼운 연산만 수행합니다.
        let control = MovementControl(forward: Int(x), strafe: Int(y))
        if active {
            heldMovement.insert(control)
        } else {
            heldMovement.remove(control)
        }
        // 단순 합계로 이동 벡터를 결정합니다. 엔진 쪽에서 필요하면 정규화/최대값 클램프를 수행합니다.
        let forward = heldMovement.reduce(0) { $0 + $1.forward }
        let strafe = heldMovement.reduce(0) { $0 + $1.strafe }
        engine.setMove(x: Double(forward), y: Double(strafe))
    }

    func guardButton(active: Bool) {
        // 가드(방어) 버튼 토글
        // 상세 동작 및 부작용:
        // - `active == true`이면 플레이어가 방어(가드) 자세로 전환됩니다. 방어 상태는 엔진의 충돌/피해 처리
        //   로직에 영향(예: 데미지 감소, 피드백 변화)을 줍니다.
        // - `active == false`이면 방어가 해제됩니다.
        // - 이 메서드는 `playerLocked`를 변경하지 않으며, 단지 엔진에 현재 가드 상태를 알립니다.
        // 호출 빈도/타이밍:
        // - 버튼이 눌리는 동안(hold) 여러 번 호출될 수 있으므로 부작용이 가볍게 유지됩니다.
        guard !active || !engine.playerLocked else { return }
        modifiers.guarding = active
        engine.setGuarding(active)
    }

    func duckButton(direction: Int, active: Bool) {
        // 더킹 버튼 처리
        // 상세 동작:
        // - `direction`은 -1(왼쪽) 또는 1(오른쪽)으로 기대됩니다.
        // - `active == true`일 때 해당 방향으로 더킹이 시작됩니다(엔진에 알림).
        // - `active == false`일 때는 동일한 방향 버튼을 다시 눌러 해제된 경우에만 더킹을 종료합니다.
        //   (즉, 다른 입력이 여전히 더킹을 유지하면 무시됩니다.)
        // 부작용 및 가시성:
        // - 더킹 상태는 엔진의 충돌 처리(머리 타깃 회피), 애니메이션 분기, 그리고 소리/햅틱 피드백에 직접 영향을 줍니다.
        // - `duckDirectionHeld`가 0이 아니면 엔진은 더킹을 활성 상태로 간주합니다.
        guard !active || !engine.playerLocked else { return }
        modifiers.setDuck(direction, active: active)
        engine.setDuck(duckDirectionHeld, active: duckDirectionHeld != 0)
    }

    func comboAttack(base: Punch) {
        // 콤보 공격 진입
        // 상세 동작:
        // - `base`는 사용자가 누른 공격 버튼 종류(예: jab, cross)를 나타냅니다.
        // - 현재의 `guardHeld`와 `duckDirectionHeld` 상태를 반영해 실제 발사될 `Punch`를 생성합니다.
        // - `PracticeEngine.startAttack`는 공격이 실제로 시작 가능한지(쿨다운, 애니메이션 상태 등)를 검사하고
        //   가능하면 true를 반환합니다. 거부되면 아무 동작도 하지 않습니다.
        // 부작용:
        // - 공격이 수락되면 단기간의 햅틱(피드백)을 트리거하여 입력에 대한 촉각적 확인을 제공합니다.
        // - 엔진이 공격을 수락하면 내부적으로 공격 애니메이션, 위치 보정, 충돌 판정 등이 이어집니다.
        if WeaveState.hook(base: base, direction: engine.player.weave.comboDirection) != nil {
            _ = engine.requestWeaveHook(base: base)
            return
        }
        guard !engine.player.weave.isActive else { return }
        let punch = selectedPunch(base: base)
        if engine.startAttack(punch) {
            HapticsManager.shared.impact(style: .light, intensity: 0.22)
            HapticsManager.shared.prepareContact()
        }
    }

    func backstep() {
        // 후진(백스텝) 시도
        // 상세 동작:
        // - 백스텝은 위치를 빠르게 뒤로 이동시키는 회피 중 하나로, 엔진의 현재 상태에 따라 허용 여부가 달라집니다.
        // - `PracticeEngine.backstep()`은 성공 시 true를 반환하고, 그 경우 햅틱 피드백을 발생시켜 사용자에게
        //   회피 수행을 명확히 알립니다.
        if engine.backstep() {
            HapticsManager.shared.impact(style: .rigid, intensity: 0.68)
        }
    }

    func selectedPunch(base: Punch) -> Punch {
        if let hook = WeaveState.hook(base: base, direction: engine.player.weave.comboDirection) { return hook }
        if engine.player.weave.isActive { return base }
        return modifiers.punch(base: base)
    }

    func weaveButton(direction: Int, active: Bool) {
        guard direction == -1 || direction == 1 else { return }
        if !active { heldWeaves.remove(direction); return }
        guard heldWeaves.insert(direction).inserted else { return }
        if engine.weave(direction: direction) {
            HapticsManager.shared.impact(style: .light, intensity: 0.22)
            publishState()
        }
    }

    func releaseHeldControls() {
        heldWeaves.removeAll()
        engine.cancelWeaveInput()
        heldMovement.removeAll()
        modifiers.reset()
        engine.setMove(x: 0, y: 0)
        engine.setGuarding(false)
        engine.setDuck(0, active: false)
    }

    /// Called by `PracticeScene` the instant a punch lands on the heavy bag, so landing a hit feels
    /// distinct (heavier haptic buzz + an impact sound) from just throwing a punch.
    func notifyBagHit(punch: Punch, damage: Int) {
        // 가방 명중 알림: PracticeScene이 즉시 호출
        // 목적 및 효과:
        // - 연습 전용 피드백으로, 무거운 타격감을 주기 위해 강한 햅틱과 임팩트 사운드를 재생합니다.
        // - `damage` 값은 가시적 진동의 강도와 사운드 파라미터에 반영됩니다.
        // 안전/스레딩:
        // - 이 메서드는 UI/메인 스레드에서 호출되어야 합니다. 햅틱과 사운드 API는 메인 컨텍스트에서
        //   안전하게 호출되는 것을 기대합니다.
        let impact = CombatImpact(attacker: .player, punch: punch, damage: damage, guarded: false,
                      guardBroken: false, counter: false, perfectCounter: false, knockout: false)
        HapticsManager.shared.playImpact(impact)
        sound.playImpact(impact)
    }

    func synchronizeHeldControls() {
        // 외부에서 엔진과 입력 상태를 동기화
        // 상세 동작:
        // - 프레임 루프(씬 업데이트)에서 호출되어 `held` 입력 상태를 엔진으로 밀어넣습니다.
        // - 공격 애니메이션이 진행 중이면 입력을 덮어쓰지 않도록 early-return 합니다.
        // - 이 함수는 가볍게 유지되어야 하며, 복잡한 계산을 포함하지 않습니다.
        guard engine.player.attack == nil, !engine.player.weave.isActive else { return }
        engine.setGuarding(guardHeld)
        engine.setDuck(duckDirectionHeld, active: duckDirectionHeld != 0)
    }

    func publishState() {
        // UI용 상태 게시
        // 목적 및 호출 위치:
        // - 뷰(예: `PracticeView`)는 이 컨트롤러의 `@Published` 프로퍼티를 구독하고 있어, 이 메서드가
        //   호출되면 화면에 보이는 상태(버튼 잠금, 체력 게이지 등)가 갱신됩니다.
        // - 주기적(예: display link 또는 타이머)으로 호출되어야 하며, 메인 스레드에서 안전하게 실행되어야 합니다.
        // 부작용:
        // - 간단한 대입만 수행하므로 성능 비용이 적습니다. 빈번한 호출 시에도 큰 부담이 되지 않습니다.
        playerLocked = engine.playerLocked
    }
}
