import RealityKit
import ARKit
import Vision
import UIKit

final class BodyTrackingAR {

    weak var arView: ARView?
    private let bodyRequest = VNDetectHumanBodyPoseRequest()
    private let processingQueue = DispatchQueue(label: "com.example.bodytracking.queue", qos: .userInitiated)
    
    // минимальный интервал между обновлениями
    private let minInterval: TimeInterval = 0.15
    private var lastProcessed: TimeInterval = 0

    // хранение энтитей
    private var bodyAnchor: AnchorEntity?
    private var jointEntities: [VNHumanBodyPoseObservation.JointName: ModelEntity] = [:]
    private var lineEntities: [ModelEntity] = []

    init(arView: ARView) {
        self.arView = arView
    }

    func process(frame: ARFrame) {
        let now = Date().timeIntervalSince1970
        if now - lastProcessed < minInterval { return }
        lastProcessed = now

        let pixelBuffer = frame.capturedImage

        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            let orientation = CGImagePropertyOrientation(interfaceOrientation:
                arViewInterfaceOrientation() ?? .portrait)
            
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
            
            do {
                try handler.perform([self.bodyRequest])
                guard let results = self.bodyRequest.results, !results.isEmpty else {
                    DispatchQueue.main.async {
                        self.clearBody()
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.updateVisualization(for: results.first!, frame: frame)
                }
            } catch {
                // print("Body pose error: \(error)")
            }
        }
    }

    private func updateVisualization(for observation: VNHumanBodyPoseObservation, frame: ARFrame) {
        guard let arView = arView else { return }

        let viewSize = arView.bounds.size
        guard let recognizedPoints = try? observation.recognizedPoints(.all) else { return }

        if bodyAnchor == nil {
            bodyAnchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
            if let bodyAnchor = bodyAnchor {
                arView.scene.addAnchor(bodyAnchor)
            }
        }

        // Точки тела, которые используем
        let joints: [VNHumanBodyPoseObservation.JointName] = [
            .neck, .root,
            .rightShoulder, .rightElbow, .rightWrist,
            .leftShoulder, .leftElbow, .leftWrist,
            .rightHip, .rightKnee, .rightAnkle,
            .leftHip, .leftKnee, .leftAnkle
        ]

        // Соединения между суставами (для линий)
        let connections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
            (.neck, .rightShoulder), (.neck, .leftShoulder),
            (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
            (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
            (.root, .rightHip), (.root, .leftHip),
            (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
            (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
            (.neck, .root)
        ]

        // создаём / обновляем точки
        for joint in joints {
            guard let point = recognizedPoints[joint], point.confidence > 0.2 else {
                jointEntities[joint]?.isEnabled = false
                continue
            }

            let normalized = CGPoint(x: CGFloat(point.location.x), y: CGFloat(point.location.y))
            let screenPoint = CGPoint(
                x: normalized.x * viewSize.width,
                y: (1.0 - normalized.y) * viewSize.height
            )

            guard let cameraTransform = arView.session.currentFrame?.camera.transform else { continue }
            let cameraPos = cameraTransform.translation
            let forward = -simd_normalize(cameraTransform.columns.2.xyz)
            let distance: Float = 1.2 // тело дальше, чем руки
            let offsetX = Float((screenPoint.x / viewSize.width) - 0.5) * distance
            let offsetY = Float((screenPoint.y / viewSize.height) - 0.5) * distance
            let worldPos = cameraPos + forward * distance + SIMD3<Float>(offsetX, -offsetY, 0)

            let jointEntity: ModelEntity
            if let existing = jointEntities[joint] {
                jointEntity = existing
                jointEntity.isEnabled = true
            } else {
                let mesh = MeshResource.generateSphere(radius: 0.01)   //SPHERE SIZE
                let mat = SimpleMaterial(color: .green, roughness: 0.4, isMetallic: false)
                jointEntity = ModelEntity(mesh: mesh, materials: [mat])
                jointEntities[joint] = jointEntity
                bodyAnchor?.addChild(jointEntity)
            }

            jointEntity.position = worldPos - (bodyAnchor?.position ?? .zero)
        }

        // удаляем старые линии
        lineEntities.forEach { $0.removeFromParent() }
        lineEntities.removeAll()

        // создаём новые линии
        for (a, b) in connections {
            if let jointA = jointEntities[a], let jointB = jointEntities[b],
               jointA.isEnabled, jointB.isEnabled {

                let start = jointA.position
                let end = jointB.position
                let direction = end - start
                let length = simd_length(direction)
                let mid = (start + end) / 2

                let lineMesh = MeshResource.generateBox(size: [0.005, 0.005, length])
                let mat = SimpleMaterial(color: .green, isMetallic: false)
                let lineEntity = ModelEntity(mesh: lineMesh, materials: [mat])

                lineEntity.position = mid
                lineEntity.look(at: end, from: mid, relativeTo: bodyAnchor)
                bodyAnchor?.addChild(lineEntity)
                lineEntities.append(lineEntity)
            }
        }
    }

    private func clearBody() {
        bodyAnchor?.removeFromParent()
        bodyAnchor = nil
        jointEntities.removeAll()
        lineEntities.removeAll()
    }
}

// MARK: - Orientation helper
private func arViewInterfaceOrientation() -> UIInterfaceOrientation? {
    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
        return scene.interfaceOrientation
    }
    return nil
}

fileprivate extension simd_float4x4 {
    var translation: SIMD3<Float> {
        SIMD3(columns.3.x, columns.3.y, columns.3.z)
    }
}

fileprivate extension simd_float4 {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
