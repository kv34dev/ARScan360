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

        // Размер view для конвертации нормализованных координат в экранные точки
        let view = arView.superview ?? arView
        let viewSize = arView.bounds.size

        // Обновляем / создаём anchor и joint entities для каждой обнаруженной руки
        for (handIndex, observation) in observations.enumerated() {
            // ensure anchor exists
            let anchorEntity: AnchorEntity
            if let existing = handAnchors[handIndex] {
                anchorEntity = existing
            } else {
                // создаём anchor, который мы будем перемещать в world space
                anchorEntity = AnchorEntity(world: SIMD3<Float>(0,0,0))
                anchorEntity.name = "handAnchor_\(handIndex)"
                handAnchors[handIndex] = anchorEntity
                arView.scene.addAnchor(anchorEntity)
            }

            // ensure joint entities dictionary exists
            if jointEntities[handIndex] == nil {
                jointEntities[handIndex] = [:]
            }

            // получаем все точки
            guard let recognizedPoints = try? observation.recognizedPoints(.all) else { continue }

            // Для каждого joint: вычисляем экранную точку, пробуем raycast, обновляем позицию sphere
            for joint in fingerJoints {
                guard let point = recognizedPoints[joint], point.confidence > 0.2 else {
                    // если точка не достоверна — скрываем соответствующую сущность (если была)
                    if let ent = jointEntities[handIndex]?[joint] {
                        ent.isEnabled = false
                    }
                    continue
                }

                // Vision coords: origin bottom-left. Screen coords (UIKit): origin top-left.
                let normalized = CGPoint(x: CGFloat(point.location.x), y: CGFloat(point.location.y))
                let screenPoint = CGPoint(x: normalized.x * viewSize.width, y: (1.0 - normalized.y) * viewSize.height)

                // Попробуем получить 3D-точку через raycast (по экранной точке)
                var worldPositionOptional: SIMD3<Float>? = nil
                if let result = arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .any).first {
                    worldPositionOptional = result.worldTransform.translation
                } else if let cameraTransform = arView.session.currentFrame?.camera.transform {
                    // fallback: расположим точку на фиксированном расстоянии перед камерой
                    let forward = -simd_normalize(cameraTransform.columns.2.xyz) // камера смотрит -Z
                    let cameraPos = cameraTransform.translation
                    let distance: Float = 0.5 // 50 cm in front
                    worldPositionOptional = cameraPos + forward * distance
                }

                guard let worldPosition = worldPositionOptional else { continue }

                // create or update entity for joint
                let jointEntity: ModelEntity
                if let existing = jointEntities[handIndex]?[joint] {
                    jointEntity = existing
                    jointEntity.isEnabled = true
                } else {
                    let mesh = MeshResource.generateSphere(radius: 0.008) // чуть побольше чтобы было видно
                    let mat = SimpleMaterial(color: .systemRed, roughness: 0.4, isMetallic: false)
                    jointEntity = ModelEntity(mesh: mesh, materials: [mat])
                    jointEntity.generateCollisionShapes(recursive: false)
                    jointEntities[handIndex]?[joint] = jointEntity
                    anchorEntity.addChild(jointEntity)
                }

                jointEntity.position = worldPosition - anchorEntity.position // local position relative to anchor
            }
        }

        // Удаляем лишние anchor'ы, если рук стало меньше
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

