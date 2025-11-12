import SwiftUI
import RealityKit
import ARKit
import Vision

struct LiDARARViewContainer: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView

        let worldConfig = ARWorldTrackingConfiguration()

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            worldConfig.frameSemantics.insert(.sceneDepth)
        }

        arView.session.run(worldConfig, options: [.resetTracking, .removeExistingAnchors])

        // Делегат Coordinator
        arView.session.delegate = context.coordinator

        // Инициализация трекеров
        context.coordinator.handTracker = HandTrackingAR(arView: arView)
        context.coordinator.bodyTracker = BodyTrackingAR(arView: arView)

        arView.debugOptions = []

        // Tap gesture для размещения куба
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    class Coordinator: NSObject, ARSessionDelegate {
        weak var arView: ARView?

        var handTracker: HandTrackingAR?
        var bodyTracker: BodyTrackingAR?

        private var scanningEnabled = true

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            handTracker?.process(frame: frame)
            bodyTracker?.process(frame: frame)
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            print("ARSession failed: \(error)")
        }

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let arView = arView else { return }
            let point = sender.location(in: arView)

            if let result = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .any).first {
                placeCube(at: result.worldTransform, in: arView)
            } else if let cameraTransform = arView.session.currentFrame?.camera.transform {
                let t = cameraTransform
                let forward = simd_normalize(t.forward3)
                let pos = t.position3 + forward * 0.5

                var mat = matrix_identity_float4x4
                mat.columns.3 = SIMD4<Float>(pos.x, pos.y, pos.z, 1)
                placeCube(at: mat, in: arView)
            }
        }

        private func placeCube(at transform: simd_float4x4, in arView: ARView) {
            let anchor = AnchorEntity(world: transform)
            let size: Float = 0.12
            let box = ModelEntity(mesh: .generateBox(size: size),
                                  materials: [SimpleMaterial(color: .green, isMetallic: false)])
            box.generateCollisionShapes(recursive: true)
            anchor.addChild(box)
            arView.scene.addAnchor(anchor)
            arView.installGestures([.translation, .rotation, .scale], for: box)
        }
    }
}

extension simd_float4x4 {
    var position3: SIMD3<Float> {
        SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }

    var forward3: SIMD3<Float> {
        SIMD3<Float>(-columns.2.x, -columns.2.y, -columns.2.z)
    }
}
