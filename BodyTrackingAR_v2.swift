import ARKit
import Vision
import UIKit
import RealityKit

final class BodyTrackingAR {
    weak var arView: ARView?
    private let bodyRequest = VNDetectHumanBodyPoseRequest()
    private let processingQueue = DispatchQueue(label: "com.example.bodytracking.queue", qos: .userInitiated)

    private let minInterval: TimeInterval = 0.15
    private var lastProcessed: TimeInterval = 0

    // 2D слой для отрисовки
    private var overlayLayer = CAShapeLayer()

    init(arView: ARView) {
        self.arView = arView
        setupOverlay()
    }

    private func setupOverlay() {
        guard let arView = arView else { return }
        overlayLayer.frame = arView.bounds
        overlayLayer.strokeColor = UIColor.green.cgColor
        overlayLayer.lineWidth = 3
        overlayLayer.fillColor = UIColor.clear.cgColor
        arView.layer.addSublayer(overlayLayer)
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
                guard let result = self.bodyRequest.results?.first else {
                    DispatchQueue.main.async { self.clearOverlay() }
                    return
                }
                DispatchQueue.main.async {
                    self.drawBodyPose(result)
                }
            } catch {
                print("Vision error: \(error)")
            }
        }
    }

    private func drawBodyPose(_ observation: VNHumanBodyPoseObservation) {
        guard let arView = arView,
              let recognizedPoints = try? observation.recognizedPoints(.all) else { return }

        let size = arView.bounds.size
        let path = UIBezierPath()

        // Точки и соединения
        let joints: [VNHumanBodyPoseObservation.JointName] = [
            .neck, .root,
            .rightShoulder, .rightElbow, .rightWrist,
            .leftShoulder, .leftElbow, .leftWrist,
            .rightHip, .rightKnee, .rightAnkle,
            .leftHip, .leftKnee, .leftAnkle
        ]

        let connections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
            (.neck, .rightShoulder), (.neck, .leftShoulder),
            (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
            (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
            (.root, .rightHip), (.root, .leftHip),
            (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
            (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
            (.neck, .root)
        ]

        func point(for joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let p = recognizedPoints[joint], p.confidence > 0.2 else { return nil }
            return CGPoint(
                x: CGFloat(p.location.x) * size.width,
                y: (1 - CGFloat(p.location.y)) * size.height
            )
        }

        for (a, b) in connections {
            if let pa = point(for: a), let pb = point(for: b) {
                path.move(to: pa)
                path.addLine(to: pb)
            }
        }

        // Обновляем слой
        overlayLayer.path = path.cgPath
    }

    private func clearOverlay() {
        overlayLayer.path = nil
    }
}

private func arViewInterfaceOrientation() -> UIInterfaceOrientation? {
    (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation
}
