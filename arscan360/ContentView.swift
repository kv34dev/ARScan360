import SwiftUI
import RealityKit
import ARKit

struct ContentView: View {
    var body: some View {
        ZStack(alignment: .top) {
            // ARView
            LiDARARViewContainer()
                .edgesIgnoringSafeArea(.all)
            
            // Overlay с названием
            VStack {
                Text("3D Environment & Human Motion Scanner")
                    .font(.system(size: 11, weight: .bold))
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .cornerRadius(30)
                    .padding(.top, 20)
                
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Настройка AR с LiDAR
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        config.frameSemantics = .sceneDepth
        arView.session.run(config)
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}
