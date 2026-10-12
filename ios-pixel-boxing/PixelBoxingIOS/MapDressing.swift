import SceneKit
import UIKit
import simd

/// Static, visual-only dressing. Add each returned tree once to an untransformed scene root.
/// Cached meshes/materials are shared: treat them as immutable. No lights, physics or update hooks.
@MainActor
public enum MapDressing {
    private typealias Vector = SIMD3<Float>

    public static func canvasMaterial() -> SCNMaterial { canvasSurface }

    static func storyCanvasMaterial(for opponent: StoryOpponent?) -> SCNMaterial {
        switch opponent {
        case .counter: counterCanvasSurface
        case .slugger: sluggerCanvasSurface
        case .rival: championshipCanvasSurface
        default: canvasSurface
        }
    }

    static func storyCenterMark(for opponent: StoryOpponent?) -> SCNNode {
        let mesh: SCNGeometry
        switch opponent {
        case .counter: mesh = counterMarkMesh
        case .slugger: mesh = sluggerMarkMesh
        case .rival: mesh = championshipMarkMesh
        default: return centerMark()
        }
        let node = horizontal(mesh, at: Vector(0, 0.12, 0))
        node.name = "mapDressing.centerMark"
        return node
    }

    static func storyRingDetails(for opponent: StoryOpponent?) -> SCNNode? {
        let title: String
        let color: UIColor
        switch opponent {
        case .counter:
            title = "CONTENDERS HALL"
            color = rgb(0.66, 0.80, 0.73)
        case .slugger:
            title = "FIGHT NIGHT"
            color = rgb(0.78, 0.59, 0.25)
        case .rival:
            title = "RIVAL  /  CHAMPIONSHIP"
            color = rgb(0.88, 0.72, 0.34)
        default: return nil
        }
        let root = group("storyRingDetails")
        let trim = matte(color, roughness: 0.85)
        let panel = eventPanel(title, subtitle: "", width: 10.8, height: 0.38, accent: color)
        for side in 0..<4 {
            let edge = group("storyApronEdge")
            edge.eulerAngles.y = Float(side) * .pi / 2
            edge.addChildNode(block(Vector(13.3, 0.045, 0.028), at: Vector(0, -0.03, 6.77), surface: trim))
            edge.addChildNode(instance(panel, at: Vector(0, -0.35, 6.81)))
            root.addChildNode(edge)
        }
        return root.flattenedClone()
    }

    /// Replaces BOTH the old cylinder and torus; canvas top remains 0.11, ink sits at 0.12.
    public static func centerMark() -> SCNNode {
        let node = horizontal(markMesh, at: Vector(0, 0.12, 0))
        node.name = "mapDressing.centerMark"
        return node
    }

    /// Add after the existing posts/ropes. Seating is owned exclusively by audience().
    public static func arenaDetails() -> SCNNode {
        let root = group("arenaDetails")
        for x: Float in [-6.15, 6.15] {
            for z: Float in [-6.15, 6.15] {
                for y: Float in [1.11, 1.57] {
                    root.addChildNode(block(Vector(0.492, 0.045, 0.492), at: Vector(x, y, z), surface: charcoal))
                }
                for y: Float in [0.68, 1.10, 1.52] {
                    for direction in [Vector(x > 0 ? -1 : 1, 0, 0), Vector(0, 0, z > 0 ? -1 : 1)] {
                        let node = instance(tubeMesh, at: Vector(x, y, z) + direction * 0.4)
                        node.simdScale = Vector(0.072, 0.36, 0.072)
                        node.simdOrientation = simd_quatf(from: Vector(0, 1, 0), to: direction)
                        root.addChildNode(node)
                    }
                }
            }
        }
        for side in 0..<4 {
            let edge = group("apronSeam")
            edge.eulerAngles.y = Float(side) * .pi / 2
            edge.addChildNode(block(Vector(13.25, 0.012, 0.008), at: Vector(0, -0.16, 6.755), surface: seamInk))
            root.addChildNode(edge)
        }
        return root
    }

    /// Replacement for buildAudience(): exactly 52 seated bodies, 84 seats, four sides, three rows.
    public static func audience() -> SCNNode {
        let root = group("audience")
        let occupied = [[0, 1, 3, 4, 6], [0, 2, 4, 6], [1, 2, 4, 5]]
        for side in 0..<4 {
            let section = group("audienceSide")
            section.eulerAngles.y = -Float(side) * .pi / 2
            for row in 0..<3 {
                for column in 0..<7 {
                    let seat = seatTemplate.clone()
                    // These are the actual existing stand centres and top surfaces, not new risers.
                    seat.simdPosition = Vector(Float(column - 3) * 2.15 + (row == 1 ? 0.2 : 0),
                                               -0.175 + Float(row) * 0.61, -8.25 - Float(row) * 1.1)
                    section.addChildNode(seat)
                    let slot = side.isMultiple(of: 2) ? column : 6 - column
                    guard occupied[row].contains(slot) else { continue }
                    let variant = side * 7 + row * 3 + column
                    seat.addChildNode(lowerBodyTemplate.clone())
                    seat.addChildNode(instance(bodyMeshes[variant % bodyMeshes.count], at: Vector(0, 0.595, 0)))
                    seat.addChildNode(instance(headMeshes[variant % headMeshes.count], at: Vector(0, 0.97, 0.035)))
                }
            }
            root.addChildNode(section)
        }
        return root
    }

    /// Replaces only the old floor and stripe loop: unchanged 30 × 30 footprint and top at y = 0.
    public static func gymFloor() -> SCNNode {
        let node = block(Vector(30, 0.1, 30), at: Vector(0, -0.05, 0), surface: woodSurface)
        node.name = "mapDressing.gymFloor"
        return node
    }

    public static func pressureGym() -> SCNNode {
        let root = group("pressureGym")
        let burgundy = matte(rgb(0.32, 0.055, 0.10), roughness: 0.9)
        let wallSurface = matte(rgb(0.48, 0.49, 0.47), roughness: 0.97)
        let floorSurface = matte(rgb(0.24, 0.25, 0.25), roughness: 0.96)
        root.addChildNode(block(Vector(36, 0.1, 32), at: Vector(0, -0.73, 0), surface: floorSurface))
        for side: Float in [-1, 1] {
            root.addChildNode(block(Vector(36, 8.4, 0.22), at: Vector(0, 3.52, side * 16), surface: wallSurface))
            root.addChildNode(block(Vector(0.22, 8.4, 32), at: Vector(side * 18, 3.52, 0), surface: wallSurface))
            root.addChildNode(block(Vector(35.8, 1.25, 0.14), at: Vector(0, -0.055, side * 15.82), surface: burgundy))
            root.addChildNode(block(Vector(0.14, 1.25, 31.6), at: Vector(side * 17.82, -0.055, 0), surface: burgundy))
            root.addChildNode(block(Vector(35.8, 0.12, 0.25), at: Vector(0, 7.2, side * 12), surface: steel))
            for x: Float in [-9, 0, 9] {
                let fixture = block(Vector(3.8, 0.08, 0.38), at: Vector(x, 7.08, side * 10), surface: charcoal)
                let tube = block(Vector(3.6, 0.025, 0.26), at: Vector(0, -0.055, 0), surface: matte(rgb(0.94, 0.95, 0.90)))
                tube.geometry?.firstMaterial?.emission.contents = rgb(0.82, 0.84, 0.78)
                tube.geometry?.firstMaterial?.emission.intensity = 0.4
                fixture.addChildNode(tube)
                root.addChildNode(fixture)
            }
            let seating = group("gymSpectators")
            seating.simdPosition = Vector(0, -0.68, side * 9)
            seating.eulerAngles.y = side > 0 ? .pi : 0
            for column in 0..<8 {
                let seat = seatTemplate.clone()
                seat.simdPosition = Vector(Float(column) * 1.65 - 5.775, 0, 0)
                if column != 2 && column != 6 {
                    seat.addChildNode(lowerBodyTemplate.clone())
                    seat.addChildNode(instance(bodyMeshes[column % bodyMeshes.count], at: Vector(0, 0.595, 0)))
                    seat.addChildNode(instance(headMeshes[column % headMeshes.count], at: Vector(0, 0.97, 0.035)))
                }
                seating.addChildNode(seat)
            }
            root.addChildNode(seating)
        }
        let sign = instance(pressureGymSignMesh, at: Vector(0, 4.65, -15.84))
        root.addChildNode(sign)
        for x: Float in [-12, 12] {
            let hanger = instance(tubeMesh, at: Vector(x, 3.65, -13.3))
            hanger.simdScale = Vector(0.025, 2.3, 0.025)
            root.addChildNode(hanger)
            let bag = SCNCylinder(radius: 0.42, height: 1.8)
            bag.radialSegmentCount = 16
            bag.firstMaterial = burgundy
            let bagNode = instance(bag, at: Vector(x, 1.6, -13.3))
            root.addChildNode(bagNode)
            for height: Float in [0.76, 2.44] {
                let collar = instance(tubeMesh, at: Vector(x, height, -13.3))
                collar.simdScale = Vector(0.425, 0.12, 0.425)
                root.addChildNode(collar)
            }
            root.addChildNode(block(Vector(3.6, 0.09, 0.7), at: Vector(x, -0.13, 12.8), surface: fabric))
            for offset: Float in [-1.4, 1.4] {
                root.addChildNode(block(Vector(0.12, 0.5, 0.55), at: Vector(x + offset, -0.43, 12.8), surface: steel))
            }
            let gloves = instance(gloveMesh, at: Vector(x, 0, 12.8))
            gloves.simdScale = Vector(1.3, 1, 1.2)
            root.addChildNode(gloves)
        }
        let judges = group("gymJudges")
        judges.simdPosition = Vector(9.2, -0.68, 0)
        judges.eulerAngles.y = -.pi / 2
        judges.addChildNode(block(Vector(3.8, 0.1, 0.85), at: Vector(0, 0.82, 0), surface: fabric))
        for x: Float in [-1.5, 1.5] {
            judges.addChildNode(block(Vector(0.1, 0.77, 0.7), at: Vector(x, 0.385, 0), surface: steel))
            let seat = seatTemplate.clone()
            seat.simdPosition = Vector(x * 0.65, 0, -0.95)
            seat.addChildNode(lowerBodyTemplate.clone())
            seat.addChildNode(instance(bodyMeshes[0], at: Vector(0, 0.595, 0)))
            seat.addChildNode(instance(headMeshes[0], at: Vector(0, 0.97, 0.035)))
            judges.addChildNode(seat)
            judges.addChildNode(block(Vector(0.4, 0.008, 0.28), at: Vector(x * 0.65, 0.88, 0), surface: matte(UIColor.white)))
        }
        root.addChildNode(judges)
        for index in 0..<3 {
            let poster = instance(posterMeshes[index % posterMeshes.count], at: Vector(-17.84, 3.3, Float(index - 1) * 4))
            poster.eulerAngles.y = .pi / 2
            root.addChildNode(poster)
        }
        return root
    }

    static func regionalHall(opponent: StoryOpponent = .outboxer) -> SCNNode {
        switch opponent {
        case .counter: return counterHall()
        case .slugger: return sluggerArena()
        case .rival: return championshipArena()
        default: break
        }
        let root = group("regionalHall")
        let wall = matte(rgb(0.62, 0.64, 0.63), roughness: 0.96)
        let floor = matte(rgb(0.27, 0.29, 0.30), roughness: 0.94)
        let stand = matte(rgb(0.37, 0.39, 0.40), roughness: 0.9)
        let accentColor: UIColor = switch opponent {
        case .counter: rgb(0.035, 0.28, 0.19)
        case .slugger: rgb(0.70, 0.55, 0.18)
        case .rival: rgb(0.80, 0.66, 0.27)
        default: rgb(0.025, 0.24, 0.30)
        }
        let accent = matte(accentColor, roughness: 0.85)
        let paper = matte(UIColor(white: 0.95, alpha: 1))
        let bannerMesh: SCNGeometry
        if opponent == .counter || opponent == .slugger || opponent == .rival {
            let panel = SCNPlane(width: 9.6, height: 1.6)
            let bannerSurface = SCNMaterial()
            bannerSurface.lightingModel = .constant
            bannerSurface.diffuse.contents = UIGraphicsImageRenderer(size: CGSize(width: 1536, height: 256)).image { context in
                UIColor(white: 0.08, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1536, height: 256))
                accentColor.setFill()
                context.fill(CGRect(x: 0, y: 232, width: 1536, height: 24))
                ("RIVAL" as NSString).draw(at: CGPoint(x: 64, y: 20), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 40, weight: .semibold), .foregroundColor: UIColor.white])
                let title = opponent == .rival ? "CHAMPIONSHIP ARENA"
                    : opponent == .counter ? "CONTENDERS HALL" : "FIGHT NIGHT ARENA"
                (title as NSString).draw(in: CGRect(x: 64, y: 80, width: 1408, height: 120), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 88, weight: .bold), .foregroundColor: UIColor.white])
            }
            panel.firstMaterial = bannerSurface
            bannerMesh = panel
        } else {
            bannerMesh = regionalHallSignMesh
        }
        root.addChildNode(block(Vector(44, 0.1, 38), at: Vector(0, -0.73, 0), surface: floor))
        if opponent == .rival {
            let entrance = group("championshipEntrance")
            entrance.addChildNode(block(Vector(6, 3.5, 0.30), at: Vector(0, 1.05, -18.4), surface: charcoal))
            for positionX: Float in [-3, 3] {
                entrance.addChildNode(block(Vector(0.18, 3.8, 0.4), at: Vector(positionX, 1.20, -18.15), surface: accent))
            }
            entrance.addChildNode(block(Vector(6.2, 0.18, 0.4), at: Vector(0, 3.10, -18.15), surface: accent))
            root.addChildNode(entrance)
        }
        for side: Float in [-1, 1] {
            root.addChildNode(block(Vector(44, 9.6, 0.24), at: Vector(0, 4.12, side * 19), surface: wall))
            root.addChildNode(block(Vector(0.24, 9.6, 38), at: Vector(side * 22, 4.12, 0), surface: wall))
            root.addChildNode(block(Vector(43.7, 0.65, 0.14), at: Vector(0, -0.25, side * 18.82), surface: accent))
            root.addChildNode(block(Vector(0.14, 0.65, 37.7), at: Vector(side * 21.82, -0.25, 0), surface: accent))
            root.addChildNode(block(Vector(25, 0.16, 0.20), at: Vector(0, 8.3, side * 10), surface: steel))
            root.addChildNode(block(Vector(0.20, 0.16, 20), at: Vector(side * 12.5, 8.3, 0), surface: steel))
            for x: Float in [-8, 0, 8] {
                let lamp = block(Vector(1.6, 0.14, 0.8), at: Vector(x, 8.12, side * 10), surface: charcoal)
                let panel = block(Vector(1.4, 0.03, 0.62), at: Vector(0, -0.085, 0), surface: paper)
                lamp.addChildNode(panel)
                root.addChildNode(lamp)
            }
            for x: Float in [-16, 16] {
                root.addChildNode(block(Vector(2.4, 3, 0.10), at: Vector(x, 0.82, side * 18.80), surface: charcoal))
                root.addChildNode(block(Vector(0.025, 2.8, 0.025), at: Vector(x, 0.82, side * 18.72), surface: paper))
            }
            let banner = instance(bannerMesh, at: Vector(0, 5.7, side * 18.75))
            banner.eulerAngles.y = side > 0 ? .pi : 0
            root.addChildNode(banner)
        }
        for side in 0..<4 {
            let section = group("regionalSpectators")
            section.eulerAngles.y = -Float(side) * .pi / 2
            for row in 0..<3 {
                let height = Float(0.42) + Float(row) * 0.52
                let depth = -9.2 - Float(row) * 1.25
                section.addChildNode(block(Vector(18.8, height, 1.22),
                    at: Vector(0, -0.68 + height * 0.5, depth), surface: stand))
                for column in 0..<10 {
                    let seat = seatTemplate.clone()
                    seat.simdPosition = Vector(Float(column) * 1.75 - 7.875, -0.68 + height, depth)
                    if (column + row + side) % 4 != 0 {
                        let variant = side * 11 + row * 5 + column
                        seat.addChildNode(lowerBodyTemplate.clone())
                        seat.addChildNode(instance(bodyMeshes[variant % bodyMeshes.count], at: Vector(0, 0.595, 0)))
                        seat.addChildNode(instance(headMeshes[variant % headMeshes.count], at: Vector(0, 0.97, 0.035)))
                    }
                    section.addChildNode(seat)
                }
            }
            section.addChildNode(block(Vector(18.8, 0.045, 0.045), at: Vector(0, 1.85, -12.4), surface: steel))
            for x: Float in [-9.3, 0, 9.3] {
                section.addChildNode(block(Vector(0.045, 1.05, 0.045), at: Vector(x, 1.325, -12.4), surface: steel))
            }
            root.addChildNode(section)
        }
        let judges = group("regionalJudges")
        judges.simdPosition = Vector(8.1, -0.68, 0)
        judges.eulerAngles.y = -.pi / 2
        judges.addChildNode(block(Vector(4.8, 0.1, 0.85), at: Vector(0, 0.82, 0), surface: charcoal))
        for x: Float in [-1.9, 1.9] {
            judges.addChildNode(block(Vector(0.1, 0.77, 0.7), at: Vector(x, 0.385, 0), surface: steel))
        }
        for index in 0..<3 {
            let x = Float(index - 1) * 1.4
            let seat = seatTemplate.clone()
            seat.simdPosition = Vector(x, 0, -0.95)
            seat.addChildNode(lowerBodyTemplate.clone())
            seat.addChildNode(instance(bodyMeshes[index % bodyMeshes.count], at: Vector(0, 0.595, 0)))
            seat.addChildNode(instance(headMeshes[index % headMeshes.count], at: Vector(0, 0.97, 0.035)))
            judges.addChildNode(seat)
            judges.addChildNode(block(Vector(0.4, 0.008, 0.28), at: Vector(x, 0.88, 0), surface: paper))
        }
        let bell = instance(sphere(0.10, surface: matte(rgb(0.64, 0.50, 0.16))), at: Vector(-2.0, 0.95, 0.08))
        judges.addChildNode(bell)
        root.addChildNode(judges)
        return root
    }

    private static func counterHall() -> SCNNode {
        let root = group("counterHall")
        let plaster = matte(rgb(0.58, 0.62, 0.60), roughness: 0.97)
        let green = matte(rgb(0.025, 0.19, 0.13), roughness: 0.91)
        let pale = matte(rgb(0.81, 0.85, 0.83))
        let floor = matte(rgb(0.24, 0.28, 0.27), roughness: 0.95)
        let stand = matte(rgb(0.32, 0.37, 0.35))
        let panelLight = luminous(rgb(0.90, 0.96, 0.93))
        root.addChildNode(block(Vector(40, 0.1, 34), at: Vector(0, -0.73, 0), surface: floor))
        let sign = eventPanel("CONTENDERS HALL", subtitle: "RIVAL  /  COUNTER", width: 8, height: 1.35,
            accent: rgb(0.53, 0.72, 0.62))
        for side: Float in [-1, 1] {
            root.addChildNode(block(Vector(40, 7.4, 0.24), at: Vector(0, 3.02, side * 17), surface: plaster))
            root.addChildNode(block(Vector(0.24, 7.4, 34), at: Vector(side * 20, 3.02, 0), surface: plaster))
            root.addChildNode(block(Vector(39.7, 1.8, 0.14), at: Vector(0, 0.22, side * 16.82), surface: green))
            root.addChildNode(block(Vector(0.14, 1.8, 33.7), at: Vector(side * 19.82, 0.22, 0), surface: green))
            let banner = instance(sign, at: Vector(0, 4.65, side * 16.76))
            banner.eulerAngles.y = side > 0 ? .pi : 0
            root.addChildNode(banner)
            for positionX: Float in [-14, -9, 9, 14] {
                root.addChildNode(block(Vector(0.20, 6.4, 0.32), at: Vector(positionX, 2.52, side * 16.65), surface: pale))
            }
            for positionZ: Float in [-12, -8, -4, 0, 4, 8, 12] {
                let acoustic = block(Vector(0.10, 2.4, 1.6), at: Vector(side * 19.74, 3.7, positionZ), surface: green)
                for offset: Float in [-0.5, 0, 0.5] {
                    acoustic.addChildNode(block(Vector(0.18, 0.92, 0.014), at: Vector(-side * 1.0, 0, offset / 1.6), surface: pale))
                }
                root.addChildNode(acoustic)
            }
            let spectators = spectatorStand(rows: 2, columns: 12, depth: 9.5, rise: 0.46,
                spacing: 1.45, surface: stand)
            spectators.eulerAngles.y = side > 0 ? .pi : 0
            root.addChildNode(spectators)
            for positionX: Float in [-7, 0, 7] {
                root.addChildNode(block(Vector(4.2, 0.12, 0.48), at: Vector(positionX, 6.25, side * 8.5), surface: charcoal))
                root.addChildNode(block(Vector(4.0, 0.035, 0.35), at: Vector(positionX, 6.17, side * 8.5), surface: panelLight))
            }
        }
        for side: Float in [-1, 1] {
            let table = group("counterOfficials")
            table.simdPosition = Vector(side * 8.5, -0.68, 0)
            table.eulerAngles.y = side > 0 ? -.pi / 2 : .pi / 2
            table.addChildNode(block(Vector(4.2, 0.12, 0.85), at: Vector(0, 0.83, 0), surface: green))
            for positionX: Float in [-1.5, 0, 1.5] {
                table.addChildNode(block(Vector(0.10, 0.77, 0.64), at: Vector(positionX, 0.385, 0), surface: steel))
                table.addChildNode(block(Vector(0.34, 0.01, 0.24), at: Vector(positionX, 0.90, 0), surface: pale))
                table.addChildNode(seatedSpectator(variant: Int(abs(positionX) * 4), at: Vector(positionX, 0, -0.9)))
            }
            root.addChildNode(table)
        }
        return root
    }

    private static func sluggerArena() -> SCNNode {
        let root = group("sluggerArena")
        let masonry = matte(rgb(0.25, 0.26, 0.27), roughness: 0.98)
        let concrete = matte(rgb(0.19, 0.20, 0.21), roughness: 0.96)
        let red = matte(rgb(0.38, 0.055, 0.065), roughness: 0.93)
        let brass = matte(rgb(0.68, 0.54, 0.24), roughness: 0.83)
        let panelLight = luminous(rgb(1, 0.88, 0.65))
        root.addChildNode(block(Vector(44, 0.1, 40), at: Vector(0, -0.73, 0), surface: concrete))
        let sign = eventPanel("FIGHT NIGHT", subtitle: "RIVAL  /  SLUGGER", width: 10.5, height: 2.0,
            accent: rgb(0.81, 0.63, 0.28))
        for side: Float in [-1, 1] {
            root.addChildNode(block(Vector(44, 8, 0.24), at: Vector(0, 3.32, side * 20), surface: masonry))
            root.addChildNode(block(Vector(0.24, 8, 40), at: Vector(side * 22, 3.32, 0), surface: masonry))
            root.addChildNode(block(Vector(43.7, 1.25, 0.15), at: Vector(0, -0.055, side * 19.82), surface: red))
            let banner = instance(sign, at: Vector(0, 4.3, side * 19.72))
            banner.eulerAngles.y = side > 0 ? .pi : 0
            root.addChildNode(banner)
            for positionZ: Float in [-15, -7.5, 0, 7.5, 15] {
                root.addChildNode(block(Vector(0.42, 7.4, 0.42), at: Vector(side * 20.5, 3.02, positionZ), surface: steel))
            }
            for positionX: Float in [-16, -12, 12, 16] {
                root.addChildNode(block(Vector(1.5, 4.0, 0.10), at: Vector(positionX, 2.6, side * 19.7), surface: red))
                root.addChildNode(block(Vector(0.16, 3.3, 0.12), at: Vector(positionX, 2.6, side * 19.62), surface: brass))
            }
        }
        for positionZ: Float in [-12, -4, 4, 12] {
            for height: Float in [6.7, 7.35] {
                root.addChildNode(beam(from: Vector(-20.5, height, positionZ), to: Vector(20.5, height, positionZ), width: 0.10, surface: steel))
            }
            for segment in 0..<10 {
                let positionX = Float(segment) * 4.1 - 20.5
                root.addChildNode(beam(from: Vector(positionX, 6.7, positionZ),
                    to: Vector(positionX + 4.1, 7.35, positionZ), width: 0.075, surface: steel))
            }
        }
        for side in 0..<4 {
            let endStand = side.isMultiple(of: 2)
            let spectators = spectatorStand(rows: endStand ? 3 : 2, columns: endStand ? 14 : 10,
                depth: endStand ? 11.5 : 10.0, rise: 0.57, spacing: 1.45, surface: concrete, full: true)
            spectators.eulerAngles.y = -Float(side) * .pi / 2
            root.addChildNode(spectators)
            let rail = group("sluggerBarrier")
            rail.eulerAngles.y = -Float(side) * .pi / 2
            rail.addChildNode(block(Vector(endStand ? 20 : 14.5, 0.065, 0.065),
                at: Vector(0, 0.43, endStand ? -9.9 : -8.6), surface: brass))
            for positionX: Float in [-6.5, 0, 6.5] {
                rail.addChildNode(block(Vector(0.07, 1.1, 0.07), at: Vector(positionX, -0.12, endStand ? -9.9 : -8.6), surface: steel))
            }
            root.addChildNode(rail)
        }
        for positionX: Float in [-9.0, 9.0] {
            for side: Float in [-1, 1] {
                let speaker = group("fightNightSpeaker")
                speaker.simdPosition = Vector(positionX, -0.68, side * 9.2)
                speaker.eulerAngles.y = side > 0 ? .pi : 0
                speaker.addChildNode(block(Vector(1.1, 2.5, 0.85), at: Vector(0, 1.25, 0), surface: charcoal))
                for height: Float in [0.65, 1.70] {
                    let cone = instance(sphere(0.31, surface: steel), at: Vector(0, height, 0.44))
                    cone.simdScale.z = 0.15
                    speaker.addChildNode(cone)
                }
                root.addChildNode(speaker.flattenedClone())
            }
        }
        for positionX: Float in [-5.5, 5.5] {
            for positionZ: Float in [-4.8, 4.8] {
                root.addChildNode(block(Vector(1.25, 0.22, 0.75), at: Vector(positionX, 6.45, positionZ), surface: charcoal))
                root.addChildNode(block(Vector(1.06, 0.045, 0.55), at: Vector(positionX, 6.31, positionZ), surface: panelLight))
            }
        }
        return root.flattenedClone()
    }

    private static func championshipArena() -> SCNNode {
        let root = group("championshipArena")
        let shell = matte(rgb(0.105, 0.11, 0.12), roughness: 0.97)
        let concrete = matte(rgb(0.20, 0.215, 0.23), roughness: 0.95)
        let gold = matte(rgb(0.76, 0.61, 0.27), roughness: 0.72)
        let goldLight = luminous(rgb(0.91, 0.74, 0.36))
        let whiteLight = luminous(rgb(0.91, 0.95, 1))
        let monitorLight = luminous(rgb(0.32, 0.43, 0.51))
        root.addChildNode(block(Vector(64, 0.1, 64), at: Vector(0, -0.73, 0), surface: shell))
        let mainSign = eventPanel("CHAMPIONSHIP", subtitle: "RIVAL  /  THE FINAL BOUT", width: 14, height: 2.6,
            accent: rgb(0.88, 0.72, 0.34))
        let board = eventPanel("RIVAL", subtitle: "CHAMPIONSHIP  /  FINAL BOUT", width: 6.5, height: 2.5,
            accent: rgb(0.88, 0.72, 0.34))
        let ribbon = eventPanel("RIVAL  /  CHAMPIONSHIP", subtitle: "", width: 25, height: 0.75,
            accent: rgb(0.88, 0.72, 0.34))
        for side in 0..<4 {
            let sector = group("championshipSector")
            sector.eulerAngles.y = -Float(side) * .pi / 2
            sector.addChildNode(block(Vector(64, 16, 0.35), at: Vector(0, 7.32, -31), surface: shell))
            sector.addChildNode(spectatorStand(rows: 6, columns: 16, depth: 10.7,
                rise: 0.63, spacing: 1.5, surface: concrete, full: true, centerAisle: true))
            sector.addChildNode(block(Vector(54, 0.38, 10), at: Vector(0, 4.05, -23.7), surface: concrete))
            sector.addChildNode(spectatorStand(rows: 3, columns: 20, depth: 21.1,
                rise: 0.70, spacing: 1.4, surface: shell, baseY: 4.25, full: true, centerAisle: true))
            sector.addChildNode(block(Vector(54, 0.24, 0.25), at: Vector(0, 4.39, -18.64), surface: charcoal))
            sector.addChildNode(block(Vector(54, 0.055, 0.12), at: Vector(0, 4.27, -18.47), surface: goldLight))
            sector.addChildNode(instance(ribbon, at: Vector(0, 4.75, -18.44)))
            for positionX: Float in [-23, -15, 15, 23] {
                sector.addChildNode(block(Vector(0.32, 12.5, 0.40), at: Vector(positionX, 5.57, -29.8), surface: steel))
                sector.addChildNode(block(Vector(0.11, 6.6, 0.12), at: Vector(positionX, 7.4, -29.52), surface: goldLight))
            }
            sector.addChildNode(instance(mainSign, at: Vector(0, 11.9, -30.65)))
            let scoreboardFace = instance(board, at: Vector(0, 10.2, -3.4))
            scoreboardFace.eulerAngles.y = .pi
            sector.addChildNode(scoreboardFace)
            sector.addChildNode(block(Vector(7.0, 0.16, 0.40), at: Vector(0, 8.86, -3.40), surface: goldLight))
            sector.addChildNode(block(Vector(7.0, 0.16, 0.40), at: Vector(0, 11.54, -3.40), surface: steel))
            if side < 2 {
                for positionX: Float in [-7.5, 7.5] {
                    sector.addChildNode(beam(from: Vector(positionX, 13.4, -7.5),
                        to: Vector(positionX, 13.4, 7.5), width: 0.18, surface: steel))
                    sector.addChildNode(beam(from: Vector(positionX, 12.8, -7.5),
                        to: Vector(positionX, 12.8, 7.5), width: 0.10, surface: steel))
                    for segment in 0..<6 {
                        let depth = Float(segment) * 2.5 - 7.5
                        sector.addChildNode(beam(from: Vector(positionX, 12.8, depth),
                            to: Vector(positionX, 13.4, depth + 2.5), width: 0.075, surface: steel))
                    }
                }
            }
            sector.addChildNode(block(Vector(0.38, 3.0, 0.38), at: Vector(0, 12.95, -3.4), surface: steel))
            for positionX: Float in [-5.5, 5.5] {
                sector.addChildNode(block(Vector(1.1, 0.20, 0.75), at: Vector(positionX, 10.55, -4.8), surface: charcoal))
                sector.addChildNode(block(Vector(0.92, 0.04, 0.58), at: Vector(positionX, 10.42, -4.8), surface: whiteLight))
            }
            root.addChildNode(sector)
        }
        root.addChildNode(block(Vector(5.4, 0.025, 22), at: Vector(0, -0.665, -19.2), surface: charcoal))
        for positionX: Float in [-2.8, 2.8] {
            root.addChildNode(block(Vector(0.09, 0.035, 22), at: Vector(positionX, -0.64, -19.2), surface: goldLight))
            root.addChildNode(block(Vector(0.48, 5.2, 1.0), at: Vector(positionX, 1.92, -29.7), surface: gold))
            for depth: Float in [-25, -21, -17, -13] {
                root.addChildNode(block(Vector(0.12, 1.05, 0.12), at: Vector(positionX, -0.15, depth), surface: steel))
            }
        }
        root.addChildNode(block(Vector(7.5, 0.35, 1.0), at: Vector(0, 4.65, -29.7), surface: gold))
        root.addChildNode(block(Vector(6.5, 4.9, 0.12), at: Vector(0, 1.77, -30.25), surface: charcoal))
        let tunnelSign = eventPanel("RIVAL", subtitle: "CHAMPIONSHIP", width: 5.4, height: 1.3,
            accent: rgb(0.88, 0.72, 0.34))
        root.addChildNode(instance(tunnelSign, at: Vector(0, 3.65, -29.12)))
        for side in 0..<4 {
            let ringside = group("championshipRingside")
            ringside.eulerAngles.y = -Float(side) * .pi / 2
            ringside.addChildNode(block(Vector(10.8, 0.10, 0.9), at: Vector(0, 0.20, -8.25), surface: charcoal))
            for positionX: Float in [-4.5, -1.5, 1.5, 4.5] {
                ringside.addChildNode(block(Vector(0.12, 0.78, 0.68), at: Vector(positionX, -0.23, -8.25), surface: steel))
                ringside.addChildNode(seatedSpectator(variant: side + Int(abs(positionX)), at: Vector(positionX, -0.68, -9.0)))
                let monitor = block(Vector(0.65, 0.36, 0.045), at: Vector(positionX, 0.46, -8.30), surface: monitorLight)
                monitor.eulerAngles.x = -.pi / 10
                ringside.addChildNode(monitor)
            }
            root.addChildNode(ringside.flattenedClone())
        }
        return root.flattenedClone()
    }

    private static func seatedSpectator(variant: Int, at position: Vector) -> SCNNode {
        let spectator = spectatorTemplates[variant % spectatorTemplates.count].clone()
        spectator.simdPosition = position
        return spectator
    }

    private static func spectatorStand(rows: Int, columns: Int, depth: Float, rise: Float,
                                       spacing: Float, surface: SCNMaterial, baseY: Float = -0.68,
                                       full: Bool = false, centerAisle: Bool = false) -> SCNNode {
        let root = group("venueSpectators")
        let width = Float(columns) * spacing
        for row in 0..<rows {
            let height = 0.44 + Float(row) * rise
            let positionZ = -depth - Float(row) * 1.30
            if centerAisle {
                let aisleWidth = spacing * 4
                let sectionWidth = (width - aisleWidth) * 0.5
                for side: Float in [-1, 1] {
                    root.addChildNode(block(Vector(sectionWidth, height, 1.29),
                        at: Vector(side * (sectionWidth + aisleWidth) * 0.5, baseY + height * 0.5, positionZ), surface: surface))
                }
            } else {
                root.addChildNode(block(Vector(width, height, 1.29), at: Vector(0, baseY + height * 0.5, positionZ), surface: surface))
            }
            for column in 0..<columns {
                if centerAisle && (columns / 2 - 2..<columns / 2 + 2).contains(column) { continue }
                let position = Vector((Float(column) - Float(columns - 1) * 0.5) * spacing, baseY + height, positionZ)
                if full || (column + row) % 4 != 0 {
                    root.addChildNode(seatedSpectator(variant: column + row * 7, at: position))
                } else {
                    let seat = seatTemplate.clone()
                    seat.simdPosition = position
                    root.addChildNode(seat)
                }
            }
        }
        return root.flattenedClone()
    }

    private static func beam(from start: Vector, to end: Vector, width: Float, surface: SCNMaterial) -> SCNNode {
        let direction = end - start
        let node = block(Vector(width, simd_length(direction), width), at: (start + end) * 0.5, surface: surface)
        node.simdOrientation = simd_quatf(from: Vector(0, 1, 0), to: simd_normalize(direction))
        return node
    }

    private static func luminous(_ color: UIColor) -> SCNMaterial {
        let surface = matte(color, roughness: 0.75)
        surface.emission.contents = color
        surface.emission.intensity = 0.65
        return surface
    }

    private static func eventPanel(_ title: String, subtitle: String, width: CGFloat, height: CGFloat,
                                   accent: UIColor) -> SCNGeometry {
        let pixelWidth: CGFloat = 1536
        let pixelHeight = max(96, (pixelWidth * height / width).rounded())
        let image = raster(pixelWidth, pixelHeight, opaque: true) { context in
            UIColor(white: 0.045, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let titleSize = min(CGFloat(pixelHeight) * (subtitle.isEmpty ? 0.58 : 0.38), 128)
            (title as NSString).draw(in: CGRect(x: 42, y: CGFloat(pixelHeight) * (subtitle.isEmpty ? 0.16 : 0.12),
                width: CGFloat(pixelWidth) - 84, height: titleSize * 1.3), withAttributes: [
                    .font: UIFont.systemFont(ofSize: titleSize, weight: .black),
                    .foregroundColor: UIColor(white: 0.96, alpha: 1), .paragraphStyle: paragraph])
            if !subtitle.isEmpty {
                (subtitle as NSString).draw(in: CGRect(x: 42, y: CGFloat(pixelHeight) * 0.66,
                    width: CGFloat(pixelWidth) - 84, height: CGFloat(pixelHeight) * 0.23), withAttributes: [
                        .font: UIFont.systemFont(ofSize: min(40, CGFloat(pixelHeight) * 0.12), weight: .semibold),
                        .foregroundColor: accent, .paragraphStyle: paragraph])
            }
            accent.setFill()
            context.fill(CGRect(x: 0, y: pixelHeight - 5, width: pixelWidth, height: 5))
        }
        return plane(width, height, image: image, unlit: true)
    }

    private static func boutCanvas(base: UIColor, ink: UIColor, title: String) -> SCNMaterial {
        let image = raster(1024, 1024, opaque: true) { context in
            context.setFillColor(base.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
            context.setStrokeColor(UIColor.black.withAlphaComponent(0.022).cgColor)
            context.setLineWidth(1)
            for pixel in stride(from: 0, to: 1024, by: 4) {
                context.move(to: CGPoint(x: pixel, y: 0))
                context.addLine(to: CGPoint(x: pixel, y: 1024))
                context.move(to: CGPoint(x: 0, y: pixel))
                context.addLine(to: CGPoint(x: 1024, y: pixel))
            }
            context.strokePath()
            context.setStrokeColor(ink.withAlphaComponent(0.32).cgColor)
            context.setLineWidth(3)
            context.stroke(CGRect(x: 105, y: 105, width: 814, height: 814))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            for edge in 0..<2 {
                context.saveGState()
                if edge == 1 {
                    context.translateBy(x: 1024, y: 1024)
                    context.rotate(by: .pi)
                }
                (title as NSString).draw(in: CGRect(x: 100, y: 42, width: 824, height: 64), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 42, weight: .black),
                    .foregroundColor: ink.withAlphaComponent(0.72), .paragraphStyle: paragraph])
                context.restoreGState()
            }
        }
        return matte(image, roughness: 0.90)
    }

    private static func boutMark(color: UIColor, title: String) -> SCNGeometry {
        let image = raster(768, 768, opaque: false) { context in
            context.clear(CGRect(x: 0, y: 0, width: 768, height: 768))
            context.setStrokeColor(color.withAlphaComponent(0.55).cgColor)
            context.setLineWidth(5)
            context.strokeEllipse(in: CGRect(x: 50, y: 50, width: 668, height: 668))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            ("RIVAL" as NSString).draw(in: CGRect(x: 70, y: 245, width: 628, height: 200), withAttributes: [
                .font: UIFont.systemFont(ofSize: 158, weight: .black), .foregroundColor: color,
                .paragraphStyle: paragraph])
            (title as NSString).draw(in: CGRect(x: 70, y: 450, width: 628, height: 65), withAttributes: [
                .font: UIFont.systemFont(ofSize: 34, weight: .bold), .foregroundColor: color,
                .paragraphStyle: paragraph])
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: 230, y: 210, width: 308, height: 7))
        }
        return plane(3.1, 3.1, image: image, alpha: true)
    }

    /// Keep the existing mats, walls, mirror, bag/pivot, rope, decorative bags and coach unchanged.
    public static func gymDetails() -> SCNNode {
        let root = group("gymDetails")
        for index in 0..<2 {
            let station = group(index == 0 ? "bench" : "gearStation")
            station.simdPosition = index == 0 ? Vector(-6.9, 0, 2.4) : Vector(6.8, 0, -2.5)
            station.eulerAngles.y = index == 0 ? -0.3 : 0.45
            let shadow = horizontal(shadowMesh, at: Vector(0, 0.006, 0))
            shadow.simdScale = Vector(index == 0 ? 2.2 : 1.3, 1.05, 1)
            station.addChildNode(shadow)
            if index == 0 {
                station.addChildNode(block(Vector(1.7, 0.08, 0.56), at: Vector(0, 0.31, 0), surface: benchWood))
                for x: Float in [-0.65, 0.65] {
                    station.addChildNode(block(Vector(0.1, 0.27, 0.44), at: Vector(x, 0.135, 0), surface: charcoal))
                }
            } else {
                station.addChildNode(block(Vector(0.85, 0.27, 0.58), at: Vector(0, 0.135, 0), surface: charcoal))
            }
            let top: Float = index == 0 ? 0.35 : 0.27
            station.addChildNode(block(Vector(0.48, 0.035, 0.4), at: Vector(-0.22, top + 0.0175, 0), surface: fabric))
            for hand in 0..<2 {
                let x = Float(hand) * 0.24 + (index == 0 ? 0.3 : 0.08)
                let glove = instance(gloveMesh, at: Vector(x, top + 0.065, -0.025))
                glove.simdScale = Vector(0.8, 0.6, 1.15)
                station.addChildNode(glove)
                station.addChildNode(block(Vector(0.13, 0.09, 0.14), at: Vector(x, top + 0.045, 0.13), surface: charcoal))
            }
            root.addChildNode(station)
        }
        // A slender wall-to-wall beam, not a ceiling: underside 5.55 is above the ~5.2 camera.
        // Raised brackets overlap the existing ±15 wall tops; no upright in the orbit corridor.
        root.addChildNode(block(Vector(30, 0.18, 0.18), at: Vector(0, 5.64, 0), surface: steel))
        for x: Float in [-14.97, 14.97] {
            root.addChildNode(block(Vector(0.18, 1.6, 0.34), at: Vector(x, 4.9, 0), surface: steel))
        }
        let hanger = instance(tubeMesh, at: Vector(0, 4.915, 0))
        hanger.simdScale = Vector(0.025, 1.27, 0.025) // 4.28–5.55: overlaps the unchanged mount at rest.
        root.addChildNode(hanger)
        let sign = instance(signMesh, at: Vector(0, 2.75, 14.9))
        sign.eulerAngles.y = .pi
        root.addChildNode(sign)
        for index in 0..<2 {
            let poster = instance(posterMeshes[index], at: Vector(-14.9, 2.3, index == 0 ? -4.5 : 4.5))
            poster.eulerAngles.y = .pi / 2
            root.addChildNode(poster)
        }
        return root
    }

    private static let charcoal = matte(rgb(0.095, 0.10, 0.115))
    private static let steel = matte(rgb(0.22, 0.235, 0.25))
    private static let seamInk = matte(rgb(0.10, 0.12, 0.16))
    private static let benchWood = matte(rgb(0.28, 0.205, 0.145))
    private static let fabric = matte(rgb(0.48, 0.47, 0.43))
    private static let canvasSurface = matte(canvasTexture, roughness: 0.85)
    private static let counterCanvasSurface = boutCanvas(base: rgb(0.80, 0.84, 0.82), ink: rgb(0.025, 0.23, 0.16), title: "CONTENDERS HALL")
    private static let sluggerCanvasSurface = boutCanvas(base: rgb(0.58, 0.60, 0.60), ink: rgb(0.14, 0.15, 0.15), title: "FIGHT NIGHT")
    private static let championshipCanvasSurface = boutCanvas(base: rgb(0.88, 0.89, 0.89), ink: rgb(0.20, 0.21, 0.23), title: "CHAMPIONSHIP")
    private static let woodSurface = matte(woodTexture, roughness: 0.82)
    private static var blockMeshes: [ObjectIdentifier: SCNGeometry] = [:]
    private static let tubeMesh: SCNGeometry = {
        let mesh = SCNCylinder(radius: 1, height: 1)
        mesh.radialSegmentCount = 8; mesh.heightSegmentCount = 1; mesh.firstMaterial = steel
        return mesh
    }()
    private static let gloveMesh = sphere(0.12, surface: matte(rgb(0.27, 0.12, 0.13)))
    private static let bodyMeshes: [SCNGeometry] = [rgb(0.13, 0.19, 0.22), rgb(0.22, 0.15, 0.16),
        rgb(0.20, 0.19, 0.15), rgb(0.15, 0.19, 0.16)].map { color in
        let mesh = SCNCapsule(capRadius: 0.18, height: 0.53)
        mesh.radialSegmentCount = 8; mesh.capSegmentCount = 2; mesh.heightSegmentCount = 1
        mesh.firstMaterial = matte(color)
        return mesh
    }
    private static let headMeshes = [rgb(0.40, 0.31, 0.25), rgb(0.29, 0.22, 0.18),
                                    rgb(0.35, 0.28, 0.23)].map { sphere(0.145, surface: matte($0)) }
    private static let seatTemplate: SCNNode = {
        let node = group("seat")
        node.addChildNode(block(Vector(0.58, 0.09, 0.5), at: Vector(0, 0.28, 0), surface: charcoal))
        node.addChildNode(block(Vector(0.58, 0.46, 0.07), at: Vector(0, 0.53, -0.24), surface: charcoal))
        node.addChildNode(block(Vector(0.1, 0.235, 0.34), at: Vector(0, 0.1175, 0), surface: charcoal))
        return node.flattenedClone()
    }()
    private static let lowerBodyTemplate: SCNNode = {
        let node = group("seatedLegs")
        node.addChildNode(block(Vector(0.33, 0.13, 0.4), at: Vector(0, 0.375, 0.08), surface: charcoal))
        for x: Float in [-0.11, 0.11] {
            node.addChildNode(block(Vector(0.12, 0.32, 0.12), at: Vector(x, 0.16, 0.25), surface: charcoal))
        }
        return node.flattenedClone()
    }()
    private static let spectatorTemplates: [SCNNode] = (0..<(bodyMeshes.count * headMeshes.count)).map { variant in
        let spectator = group("seatedSpectator")
        spectator.addChildNode(seatTemplate.clone())
        spectator.addChildNode(lowerBodyTemplate.clone())
        spectator.addChildNode(instance(bodyMeshes[variant % bodyMeshes.count], at: Vector(0, 0.595, 0)))
        spectator.addChildNode(instance(headMeshes[variant % headMeshes.count], at: Vector(0, 0.97, 0.035)))
        return spectator.flattenedClone()
    }
    private static let markMesh = plane(2.6, 2.6, image: markTexture, alpha: true)
    private static let counterMarkMesh = boutMark(color: rgb(0.035, 0.25, 0.17), title: "CONTENDERS")
    private static let sluggerMarkMesh = boutMark(color: rgb(0.18, 0.19, 0.20), title: "FIGHT NIGHT")
    private static let championshipMarkMesh = boutMark(color: rgb(0.27, 0.23, 0.13), title: "CHAMPIONSHIP")
    private static let shadowMesh = plane(1, 1, image: shadowTexture, alpha: true, unlit: true)
    private static let signMesh = plane(2.1, 0.7875, image: signTexture)
    private static let posterMeshes = (0..<2).map { plane(1, 1.5, image: posterTexture($0)) }
    private static let pressureGymSignMesh = plane(7, 1.6, image: raster(1120, 256, opaque: true) { context in
        context.setFillColor(rgb(0.32, 0.055, 0.10).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1120, height: 256))
        let text = "RIVAL BOXING CLUB" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 76, weight: .black), .foregroundColor: UIColor(white: 0.94, alpha: 1)
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: (1120 - size.width) * 0.5, y: (256 - size.height) * 0.5), withAttributes: attributes)
    })
    private static let regionalHallSignMesh = plane(10, 1.8, image: raster(1280, 256, opaque: true) { context in
        context.setFillColor(rgb(0.025, 0.15, 0.27).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1280, height: 256))
        let title = "RIVAL REGIONAL SERIES" as NSString
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 72, weight: .black), .foregroundColor: UIColor(white: 0.96, alpha: 1)
        ]
        let size = title.size(withAttributes: titleAttributes)
        title.draw(at: CGPoint(x: (1280 - size.width) * 0.5, y: 46), withAttributes: titleAttributes)
        let detail = "6 ROUND BOUT" as NSString
        let detailAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: rgb(0.78, 0.84, 0.86)
        ]
        let detailSize = detail.size(withAttributes: detailAttributes)
        detail.draw(at: CGPoint(x: (1280 - detailSize.width) * 0.5, y: 160), withAttributes: detailAttributes)
    })

    private static let canvasTexture = raster(1024, 1024, opaque: true) { context in
        context.setFillColor(rgb(0.78, 0.84, 0.86).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        for pixel in stride(from: 0, to: 1024, by: 4) {
            context.setFillColor(UIColor.black.withAlphaComponent(0.016).cgColor)
            context.fill(CGRect(x: pixel, y: 0, width: 1, height: 1024))
            context.setFillColor(UIColor.white.withAlphaComponent(0.028).cgColor)
            context.fill(CGRect(x: 0, y: pixel, width: 1024, height: 1))
        }
        context.setLineWidth(1)
        for index in 0..<150 {
            let x = noise(index * 3) * 960 + 32, y = noise(index * 3 + 1) * 960 + 32
            context.setStrokeColor(UIColor.black.withAlphaComponent(0.012 + noise(index) * 0.012).cgColor)
            context.strokeEllipse(in: CGRect(x: x, y: y, width: 6 + noise(index * 3 + 2) * 28, height: 2))
        }
    }
    private static let woodTexture = raster(1024, 1024, opaque: true) { context in
        context.setFillColor(rgb(0.38, 0.26, 0.15).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        for column in 0..<40 {
            let x = CGFloat(column) * 25.6
            var y = -noise(column + 500) * 150
            var board = 0
            while y < 1024 {
                let seed = column * 97 + board + 1000
                let length = 95 + noise(seed) * 130, tint = (noise(seed + 3000) - 0.5) * 0.035
                context.setFillColor(rgb(0.365 + tint, 0.25 + tint, 0.145 + tint * 0.6).cgColor)
                context.fill(CGRect(x: x, y: y, width: 25.6, height: length))
                context.setStrokeColor(UIColor.black.withAlphaComponent(0.13).cgColor)
                context.setLineWidth(0.65)
                context.stroke(CGRect(x: x, y: y, width: 25.6, height: length))
                context.setFillColor(UIColor.black.withAlphaComponent(0.035).cgColor)
                context.fill(CGRect(x: x + 5 + noise(seed + 1) * 14, y: y + 8, width: 0.6, height: length - 16))
                y += length; board += 1
            }
        }
    }
    private static let markTexture = raster(512, 512, opaque: false) { context in
        let unit: CGFloat = 512 / 2.6
        context.setFillColor(rgb(0.055, 0.12, 0.19).cgColor)
        context.fillEllipse(in: CGRect(x: 256 - 1.28 * unit, y: 256 - 1.28 * unit, width: 2.56 * unit, height: 2.56 * unit))
        context.setStrokeColor(rgb(0.92, 0.66, 0.16).cgColor)
        context.setLineWidth(0.07 * unit)
        context.strokeEllipse(in: CGRect(x: 256 - 0.86 * unit, y: 256 - 0.86 * unit, width: 1.72 * unit, height: 1.72 * unit))
    }
    private static let shadowTexture = raster(256, 256, opaque: false) { context in
        let colors = [UIColor.black.withAlphaComponent(0.16).cgColor, UIColor.clear.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            context.drawRadialGradient(gradient, startCenter: CGPoint(x: 128, y: 128), startRadius: 0,
                                       endCenter: CGPoint(x: 128, y: 128), endRadius: 124, options: [])
        }
    }
    private static let signTexture = raster(512, 192, opaque: true) { context in
        context.setFillColor(rgb(0.13, 0.14, 0.15).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 512, height: 192))
        let text = "RIVAL" as NSString, font = UIFont.systemFont(ofSize: 100, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: rgb(0.70, 0.68, 0.61)]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: (512 - size.width) / 2, y: (192 - size.height) / 2), withAttributes: attributes)
    }
    private static func posterTexture(_ pose: Int) -> UIImage {
        raster(512, 768, opaque: true) { context in
            context.setFillColor(rgb(0.48, 0.46, 0.42).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 512, height: 768))
            context.setFillColor(rgb(0.14, 0.17, 0.19).cgColor)
            context.fillEllipse(in: CGRect(x: 206, y: 140, width: 74, height: 74))
            context.setStrokeColor(rgb(0.14, 0.17, 0.19).cgColor)
            context.setLineWidth(24); context.setLineCap(.round); context.setLineJoin(.round)
            let fist = pose == 0 ? CGPoint(x: 189, y: 230) : CGPoint(x: 422, y: 236)
            let paths: [[CGPoint]] = [
                [CGPoint(x: 243, y: 215), CGPoint(x: 230, y: 295), CGPoint(x: 247, y: 436)],
                [CGPoint(x: 247, y: 436), CGPoint(x: 205, y: 540), CGPoint(x: 150, y: 627)],
                [CGPoint(x: 247, y: 436), CGPoint(x: 318, y: 520), CGPoint(x: 352, y: 613)],
                [CGPoint(x: 231, y: 262), pose == 0 ? CGPoint(x: 172, y: 331) : CGPoint(x: 330, y: 245), fist],
                [CGPoint(x: 236, y: 282), CGPoint(x: 285, y: 333), CGPoint(x: 297, y: 241)],
            ]
            for path in paths { context.addLines(between: path); context.strokePath() }
            context.setFillColor(rgb(0.34, 0.15, 0.16).cgColor)
            for point in [fist, CGPoint(x: 297, y: 241)] {
                context.fillEllipse(in: CGRect(x: point.x - 21, y: point.y - 24, width: 42, height: 48))
            }
        }
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
    private static func matte(_ contents: Any, roughness: CGFloat = 0.9) -> SCNMaterial {
        let surface = SCNMaterial()
        surface.lightingModel = .physicallyBased; surface.diffuse.contents = contents
        surface.diffuse.minificationFilter = .linear; surface.diffuse.magnificationFilter = .linear
        surface.diffuse.mipFilter = .linear
        surface.roughness.contents = roughness; surface.metalness.contents = 0
        return surface
    }
    private static func group(_ name: String) -> SCNNode {
        let node = SCNNode(); node.name = "mapDressing.\(name)"; node.castsShadow = false
        return node
    }
    private static func instance(_ mesh: SCNGeometry, at position: Vector) -> SCNNode {
        let node = SCNNode(geometry: mesh); node.simdPosition = position; node.castsShadow = false
        return node
    }
    private static func block(_ size: Vector, at position: Vector, surface: SCNMaterial) -> SCNNode {
        let key = ObjectIdentifier(surface)
        if blockMeshes[key] == nil {
            let mesh = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
            mesh.firstMaterial = surface; blockMeshes[key] = mesh
        }
        let node = SCNNode(geometry: blockMeshes[key])
        node.simdPosition = position; node.simdScale = size; node.castsShadow = false
        return node
    }
    private static func sphere(_ radius: CGFloat, surface: SCNMaterial) -> SCNGeometry {
        let mesh = SCNSphere(radius: radius); mesh.segmentCount = 10; mesh.firstMaterial = surface
        return mesh
    }
    private static func plane(_ width: CGFloat, _ height: CGFloat, image: UIImage, alpha: Bool = false, unlit: Bool = false) -> SCNGeometry {
        let mesh = SCNPlane(width: width, height: height), surface = matte(image, roughness: 0.85)
        surface.diffuse.wrapS = .clamp; surface.diffuse.wrapT = .clamp; surface.diffuse.mipFilter = .linear
        surface.lightingModel = unlit ? .constant : .physicallyBased
        surface.readsFromDepthBuffer = true; surface.writesToDepthBuffer = !alpha
        surface.transparencyMode = .aOne; surface.blendMode = .alpha; mesh.firstMaterial = surface
        return mesh
    }
    private static func horizontal(_ mesh: SCNGeometry, at position: Vector) -> SCNNode {
        let node = instance(mesh, at: position); node.eulerAngles.x = -.pi / 2; node.renderingOrder = 1
        return node
    }
    private static func raster(_ width: CGFloat, _ height: CGFloat, opaque: Bool, draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = opaque; format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { draw($0.cgContext) }
    }
    private static func noise(_ seed: Int) -> CGFloat {
        var value = UInt64(truncatingIfNeeded: seed) &+ 0x9e3779b97f4a7c15
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        return CGFloat((value ^ (value >> 27)) & 0xffff) / 65535
    }
}