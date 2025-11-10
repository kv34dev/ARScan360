import RealityKit
import ARKit
import Vision
import UIKit

final class HandTrackingAR {

    // MARK: - Config
    weak var arView: ARView?
    private let handPoseRequest = VNDetectHumanHandPoseRequest()
    private let processingQueue = DispatchQueue(label: "com.example.handtracking.queue", qos: .userInitiated)

    private let minInterval: TimeInterval = 0.1
    private var lastProcessed: TimeInterval = 0

    private let fingerJoints: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip
    ]

    private var handAnchors: [Int: AnchorEntity] = [:]
    private var jointEntities: [Int: [VNHumanHandPoseObservation.JointName: ModelEntity]] = [:]
    private var lineEntities: [Int: [String: ModelEntity]] = [:] // ключ = "joint1_joint2"

    init(arView: ARView) {
        self.arView = arView
        handPoseRequest.maximumHandCount = 2
    }

    func process(frame: ARFrame) {
        let now = Date().timeIntervalSince1970
        if now - lastProcessed < minInterval { return }
        lastProcessed = now

        let pixelBuffer = frame.capturedImage
        let interfaceOrientation =
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }
                .first ?? .portrait

        let orientation = CGImagePropertyOrientation(interfaceOrientation: interfaceOrientation)

        processingQueue.async { [weak self] in
            guard let self = self else { return }
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                orientation: orientation,
                                                options: [:])
            do {
                try handler.perform([self.handPoseRequest])
                guard let observations = self.handPoseRequest.results, !observations.isEmpty else {
                    DispatchQueue.main.async { self.clearHandEntities() }
                    return
                }
                DispatchQueue.main.async {
                    self.updateVisualization(for: observations, frame: frame)
                }
            } catch {
                // print("Hand pose error: \(error)")
            }
        }
    }

    private func updateVisualization(for observations: [VNHumanHandPoseObservation], frame: ARFrame) {
        guard let arView = arView else { return }
        let viewSize = arView.bounds.size

        for (handIndex, observation) in observations.enumerated() {
            let anchorEntity: AnchorEntity
            if let existing = handAnchors[handIndex] {
                anchorEntity = existing
            } else {
                anchorEntity = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
                anchorEntity.name = "handAnchor_\(handIndex)"
                handAnchors[handIndex] = anchorEntity
                arView.scene.addAnchor(anchorEntity)
            }

            if jointEntities[handIndex] == nil { jointEntities[handIndex] = [:] }
            if lineEntities[handIndex] == nil { lineEntities[handIndex] = [:] }

            guard let recognizedPoints = try? observation.recognizedPoints(.all) else { continue }

            var jointWorldPositions: [VNHumanHandPoseObservation.JointName: SIMD3<Float>] = [:]

            for joint in fingerJoints {
                guard let point = recognizedPoints[joint], point.confidence > 0.3 else {
                    jointEntities[handIndex]?[joint]?.isEnabled = false
                    continue
                }

                let normalized = CGPoint(x: CGFloat(point.location.x), y: CGFloat(point.location.y))
                let screenPoint = CGPoint(x: normalized.x * viewSize.width,
                                          y: (1.0 - normalized.y) * viewSize.height)

                guard let ray = arView.ray(through: screenPoint) else { continue }

                // "протягиваем" 40 см вглубь
                let distance: Float = 0.4
                let worldPos = ray.origin + ray.direction * distance
                jointWorldPositions[joint] = worldPos

                let jointEntity: ModelEntity
                if let existing = jointEntities[handIndex]?[joint] {
                    jointEntity = existing
                    jointEntity.isEnabled = true
                } else {
                    let mesh = MeshResource.generateSphere(radius: 0.000)   //SPHERE SIZE
                    let mat = SimpleMaterial(color: .green, roughness: 0.4, isMetallic: false)
                    jointEntity = ModelEntity(mesh: mesh, materials: [mat])
                    jointEntities[handIndex]?[joint] = jointEntity
                    anchorEntity.addChild(jointEntity)
                }

                let lerpFactor: Float = 0.25
                let currentPos = jointEntity.position(relativeTo: anchorEntity)
                jointEntity.position = simd_mix(currentPos, worldPos - anchorEntity.position, SIMD3<Float>(repeating: lerpFactor))
            }

            // соединения суставов в виде линий
            let fingers: [[VNHumanHandPoseObservation.JointName]] = [
                [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip],
                [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
                [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip],
                [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip],
                [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip]
            ]

            for finger in fingers {
                for i in 0..<(finger.count - 1) {
                    let j1 = finger[i], j2 = finger[i + 1]
                    guard let p1 = jointWorldPositions[j1], let p2 = jointWorldPositions[j2] else { continue }
                    let key = "\(j1.rawValue)_\(j2.rawValue)"

                    let lineEntity: ModelEntity
                    if let existing = lineEntities[handIndex]?[key] {
                        lineEntity = existing
                    } else {
                        let mesh = MeshResource.generateBox(size: SIMD3<Float>(0.002, 0.002, 0.1))  //LINE SIZE
                        let mat = SimpleMaterial(color: .green, roughness: 0.3, isMetallic: false)
                        lineEntity = ModelEntity(mesh: mesh, materials: [mat])
                        lineEntities[handIndex]?[key] = lineEntity
                        anchorEntity.addChild(lineEntity)
                    }

                    let middle = (p1 + p2) / 2
                    let direction = simd_normalize(p2 - p1)
                    let distance = simd_length(p2 - p1)

                    lineEntity.position = middle - anchorEntity.position
                    lineEntity.scale = SIMD3<Float>(repeating: 1)
                    lineEntity.scale.z = distance / 0.1
                    lineEntity.orientation = simd_quatf(from: [0, 0, 1], to: direction)
                }
            }
        }
    }

    private func clearHandEntities() {
        for (_, anchor) in handAnchors { anchor.removeFromParent() }
        handAnchors.removeAll()
        jointEntities.removeAll()
        lineEntities.removeAll()
    }
}

fileprivate extension simd_float4x4 {
    var translation: SIMD3<Float> { SIMD3(columns.3.x, columns.3.y, columns.3.z) }
}
fileprivate extension simd_float4 {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}

// MARK: - Orientation fix for Vision
extension CGImagePropertyOrientation {
    init(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portraitUpsideDown: self = .left
        case .landscapeLeft: self = .up
        case .landscapeRight: self = .down
        default: self = .right
        }
    }
}
