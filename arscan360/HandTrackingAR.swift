import RealityKit
import ARKit
import Vision
import UIKit

/// HandTrackingAR — не является ARSessionDelegate.
/// Coordinator будет вызывать process(frame:) каждый кадр.
final class HandTrackingAR {

    // MARK: - Config
    weak var arView: ARView?
    private let handPoseRequest = VNDetectHumanHandPoseRequest()
    private let processingQueue = DispatchQueue(label: "com.example.handtracking.queue", qos: .userInitiated)

    // throttle: минимальный интервал между Vision вызовами (сек)
    private let minInterval: TimeInterval = 0.1 // ~10 FPS
    private var lastProcessed: TimeInterval = 0

    // joints we track
    private let fingerJoints: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip
    ]

    // reuse entities: one anchor per detected hand, with sphere entities for joints
    // keys: handIndex (0..n)
    private var handAnchors: [Int: AnchorEntity] = [:]
    private var jointEntities: [Int: [VNHumanHandPoseObservation.JointName: ModelEntity]] = [:]

    init(arView: ARView) {
        self.arView = arView
        handPoseRequest.maximumHandCount = 2 // поддерживаем до 2-х рук
    }

    // MARK: - Public: вызывается из Coordinator.session(_:didUpdate:)
    func process(frame: ARFrame) {
        let now = Date().timeIntervalSince1970
        if now - lastProcessed < minInterval { return } // throttle
        lastProcessed = now

        // Копируем pixel buffer для безопасной работы в фоне
        let pixelBuffer = frame.capturedImage

        // Выполняем Vision на фоне
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                orientation: .up,
                                                options: [:])
            do {
                try handler.perform([self.handPoseRequest])
                guard let observations = self.handPoseRequest.results, !observations.isEmpty else {
                    // если рук нет — удалим сущности на главном потоке
                    DispatchQueue.main.async {
                        self.clearHandEntities()
                    }
                    return
                }
                // Обновляем визуализацию на главном потоке
                DispatchQueue.main.async {
                    self.updateVisualization(for: observations, frame: frame)
                }
            } catch {
                // не ломаем main thread
                // можно логировать
                // print("Hand pose error: \(error)")
            }
        }
    }

    // MARK: - Visualization helpers (main thread)
    private func updateVisualization(for observations: [VNHumanHandPoseObservation], frame: ARFrame) {
        guard let arView = arView else { return }

        let viewSize = arView.bounds.size

        for (handIndex, observation) in observations.enumerated() {
            let anchorEntity: AnchorEntity
            if let existing = handAnchors[handIndex] {
                anchorEntity = existing
            } else {
                anchorEntity = AnchorEntity(world: SIMD3<Float>(0,0,0))
                anchorEntity.name = "handAnchor_\(handIndex)"
                handAnchors[handIndex] = anchorEntity
                arView.scene.addAnchor(anchorEntity)
            }

            if jointEntities[handIndex] == nil {
                jointEntities[handIndex] = [:]
            }

            guard let recognizedPoints = try? observation.recognizedPoints(.all) else { continue }

            // Для каждого joint
            for joint in fingerJoints {
                guard let point = recognizedPoints[joint], point.confidence > 0.3 else {
                    jointEntities[handIndex]?[joint]?.isEnabled = false
                    continue
                }

                let normalized = CGPoint(x: CGFloat(point.location.x), y: CGFloat(point.location.y))
                let screenPoint = CGPoint(x: normalized.x * viewSize.width,
                                          y: (1.0 - normalized.y) * viewSize.height)

                // Получаем позицию камеры
                guard let cameraTransform = arView.session.currentFrame?.camera.transform else { continue }
                let cameraPos = cameraTransform.translation
                let forward = -simd_normalize(cameraTransform.columns.2.xyz)

                // Расстояние от камеры до руки (примерно 0.4 м)
                let distance: Float = 0.4

                // Вычисляем положение в 3D относительно центра экрана
                let offsetX = Float((screenPoint.x / viewSize.width) - 0.5) * distance
                let offsetY = Float((screenPoint.y / viewSize.height) - 0.5) * distance
                let worldPos = cameraPos + forward * distance + SIMD3<Float>(offsetX, -offsetY, 0)

                let jointEntity: ModelEntity
                if let existing = jointEntities[handIndex]?[joint] {
                    jointEntity = existing
                    jointEntity.isEnabled = true
                } else {
                    let mesh = MeshResource.generateSphere(radius: 0.007)
                    let mat = SimpleMaterial(color: .green, roughness: 0.4, isMetallic: false)
                    jointEntity = ModelEntity(mesh: mesh, materials: [mat])
                    jointEntity.generateCollisionShapes(recursive: false)
                    jointEntities[handIndex]?[joint] = jointEntity
                    anchorEntity.addChild(jointEntity)
                }

                // Плавное движение
                let lerpFactor: Float = 0.2
                let currentPos = jointEntity.position(relativeTo: anchorEntity)
                jointEntity.position = simd_mix(currentPos, worldPos - anchorEntity.position, SIMD3<Float>(repeating: lerpFactor))
            }
        }

        // Удаляем лишние руки
        let observedCount = observations.count
        for (index, anchor) in handAnchors {
            if index >= observedCount {
                anchor.removeFromParent()
                handAnchors.removeValue(forKey: index)
                jointEntities.removeValue(forKey: index)
            }
        }
    }

    // MARK: - Utility
    private func clearHandEntities() {
        for (_, anchor) in handAnchors {
            anchor.removeFromParent()
        }
        handAnchors.removeAll()
        jointEntities.removeAll()
    }
}

// MARK: - SIMD helpers
fileprivate extension simd_float4x4 {
    var translation: SIMD3<Float> {
        return SIMD3(columns.3.x, columns.3.y, columns.3.z)
    }
}

fileprivate extension simd_float4 {
    var xyz: SIMD3<Float> {
        SIMD3(x, y, z)
    }
}

