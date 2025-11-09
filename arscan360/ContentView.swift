import SwiftUI
import RealityKit
import ARKit

struct ContentView: View {
    var body: some View {
        ZStack(alignment: .top) {
            LiDARARViewContainer()
                .edgesIgnoringSafeArea(.all)
            VStack(spacing: 8) {
                HStack {
                    Text("LiDAR Scan • точная постановка")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 16)
                ScanOverlay() // простая overlay-компонента для состояния
                    .padding(.horizontal, 16)
            }
            .padding(.top, 28)
        }
    }
}

struct ScanOverlay: View {
    // Communicates via NotificationCenter (simple)
    @State private var stateText: String = "Ожидание..."
    @State private var anchorsCount: Int = 0

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(stateText)
                    .font(.system(size: 13, weight: .medium))
                Text("Mesh anchors: \(anchorsCount)")
                    .font(.system(size: 12))
                    .opacity(0.8)
            }
            Spacer()
            Button(action: {
                NotificationCenter.default.post(name: .toggleScanMode, object: nil)
            }) {
                Text("Toggle Scan")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
            }
        }
        .padding(10)
        .background(.thinMaterial)
        .cornerRadius(12)
        .onReceive(NotificationCenter.default.publisher(for: .scanStateUpdate)) { notif in
            if let info = notif.userInfo as? [String:Any] {
                if let state = info["state"] as? String { self.stateText = state }
                if let count = info["anchorsCount"] as? Int { self.anchorsCount = count }
            }
        }
    }
}

extension Notification.Name {
    static let toggleScanMode = Notification.Name("toggleScanMode")
    static let scanStateUpdate = Notification.Name("scanStateUpdate")
    static let placedObjectInfo = Notification.Name("placedObjectInfo")
}
