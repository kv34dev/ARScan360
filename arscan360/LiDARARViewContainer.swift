import SwiftUI
import RealityKit
import ARKit

struct LiDARARViewContainer: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView

        // настройка сессии: worldTracking + mesh reconstruction
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = []
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        // семантика глубины для улучшений (если поддерживается)
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        // запуск
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        // установка делегата сессии для получения anchor updates
        arView.session.delegate = context.coordinator

        // тап-жест для размещения
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)

        // удобное отображение для отладки: показать feature points
        arView.debugOptions.insert(.showFeaturePoints)

        // подписка на переключение режима сканирования
        NotificationCenter.default.addObserver(context.coordinator,
                                               selector: #selector(Coordinator.toggleScanMode),
                                               name: .toggleScanMode,
                                               object: nil)

        // инициализация UI state
        context.coordinator.updateScanStateUI(state: "Scanning...", anchorsCount: 0)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    class Coordinator: NSObject, ARSessionDelegate {
        weak var arView: ARView?
        private var scanningEnabled: Bool = true

        // handleTap: raycast against existing mesh geometry -> place object
        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let arView = arView else { return }
            let loc = sender.location(in: arView)

            // сначала пробуем raycast против существующей геометрии меша
            if let result = arView.raycast(from: loc, allowing: .existingPlaneGeometry, alignment: .any).first {
                placeObject(at: result.worldTransform)
                return
            }
            // fallback: estimated plane (если mesh не доступен в этой точке)
            if let result2 = arView.raycast(from: loc, allowing: .estimatedPlane, alignment: .any).first {
                placeObject(at: result2.worldTransform)
                return
            }

            // если ничего не найдено — можно уведомить пользователя
            updateScanStateUI(state: "No surface found at tap", anchorsCount: currentMeshAnchorCount())
        }

        // размещение объекта: небольшой куб + жесты
        private func placeObject(at transform: simd_float4x4) {
            guard let arView = arView else { return }

            let anchor = AnchorEntity(world: transform)
            let size: Float = 0.12
            let box = ModelEntity(mesh: .generateBox(size: size),
                                  materials: [SimpleMaterial(color: UIColor(red: 0.9, green: 0.45, blue: 0.15, alpha: 1.0), isMetallic: false)])
            box.generateCollisionShapes(recursive: true)
            anchor.addChild(box)
            arView.scene.addAnchor(anchor)

            // устанавливаем жесты RealityKit (перемещение/вращение/масштаб)
            arView.installGestures([.translation, .rotation, .scale], for: box)

            updateScanStateUI(state: "Object placed", anchorsCount: currentMeshAnchorCount())

            NotificationCenter.default.post(name: .placedObjectInfo, object: nil, userInfo: ["transform": transform])
        }

        // переключение режима сканирования
        @objc func toggleScanMode() {
            scanningEnabled.toggle()
            guard let arView = arView else { return }

            if scanningEnabled {
                let config = ARWorldTrackingConfiguration()
                if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                    config.sceneReconstruction = .mesh
                }
                if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                    config.frameSemantics.insert(.sceneDepth)
                }
                arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
                updateScanStateUI(state: "Scanning...", anchorsCount: currentMeshAnchorCount())
            } else {
                let config = ARWorldTrackingConfiguration()
                // убираем sceneReconstruction
                if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                    config.frameSemantics.remove(.sceneDepth)
                }
                arView.session.run(config, options: [])
                updateScanStateUI(state: "Scan paused", anchorsCount: currentMeshAnchorCount())
            }
        }

        // MARK: - ARSessionDelegate: наблюдаем за anchors (mesh anchors)
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            updateScanStateUI(state: scanningEnabled ? "Scanning..." : "Paused", anchorsCount: currentMeshAnchorCount())
        }
        func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            updateScanStateUI(state: scanningEnabled ? "Scanning..." : "Paused", anchorsCount: currentMeshAnchorCount())
        }
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            updateScanStateUI(state: scanningEnabled ? "Scanning..." : "Paused", anchorsCount: currentMeshAnchorCount())
        }

        // helper
        func currentMeshAnchorCount() -> Int {
            guard let arView = arView else { return 0 }
            let anchors = arView.session.currentFrame?.anchors ?? []
            return anchors.reduce(0) { $0 + ( $1 is ARMeshAnchor ? 1 : 0 ) }
        }

        func updateScanStateUI(state: String, anchorsCount: Int) {
            NotificationCenter.default.post(name: .scanStateUpdate, object: nil, userInfo: ["state": state, "anchorsCount": anchorsCount])
        }
    }
}
