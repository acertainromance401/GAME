import XCTest
import SceneKit
@testable import RIVAL

@MainActor
final class MapDressingTests: XCTestCase {
    func testArenaRetainsApprovedLightRigAndCamera() throws {
        let scene = Arena3DScene(engine: CombatEngine(persistHabits: false))
        let lights = scene.rootNode.childNodes.compactMap(\.light)
        XCTAssertEqual(lights.count, 5)
        XCTAssertEqual(lights.filter { $0.type == .ambient }.first?.intensity, 260)
        let spots = lights.filter { $0.type == .spot }
        XCTAssertEqual(spots.map(\.intensity).sorted(), [1050, 1050, 1050, 1650])
        XCTAssertEqual(spots.filter(\.castsShadow).count, 1)
        XCTAssertTrue(spots.allSatisfy { $0.spotInnerAngle == 24 && $0.spotOuterAngle == 70 })
        XCTAssertEqual(scene.cameraNode.camera?.fieldOfView, 50)
        XCTAssertEqual(scene.cameraNode.camera?.bloomIntensity, 0.22)
        XCTAssertNotNil(scene.rootNode.childNode(withName: "mapDressing.centerMark", recursively: true))
        XCTAssertNotNil(scene.rootNode.childNode(withName: "mapDressing.audience", recursively: true))
    }

    func testDressingHasNoLightsOrPhysicsAndGymKeepsItsFloorFootprint() {
        let trees = [MapDressing.centerMark(), MapDressing.arenaDetails(), MapDressing.audience(),
                     MapDressing.gymFloor(), MapDressing.gymDetails()]
        for tree in trees {
            tree.enumerateChildNodes { node, _ in
                XCTAssertNil(node.light)
                XCTAssertNil(node.physicsBody)
            }
        }
        let floor = MapDressing.gymFloor()
        XCTAssertEqual(floor.simdScale.x, 30)
        XCTAssertEqual(floor.simdScale.z, 30)
        XCTAssertEqual(floor.position.y, -0.05, accuracy: 0.0001)
        let audience = MapDressing.audience()
        XCTAssertEqual(audience.childNodes.count, 4)
        XCTAssertTrue(audience.childNodes.allSatisfy { $0.childNodes.count == 21 })
        XCTAssertEqual(MapDressing.centerMark().position.y, 0.12, accuracy: 0.0001)
    }
}