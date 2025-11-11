# ARScan360 — 3D Environment & Human Motion Scanner

ARScan360 is an iOS augmented reality application that scans the environment in 360° and detects people in real time. Using advanced ARKit and RealityKit features, it can recognize human bodies, draw skeletal contours, and track hand and finger movements.

In LiDAR Scan Mode (available on devices with a LiDAR sensor), users can also place virtual 3D objects — currently, a cube — on flat or non-flat surfaces in the real world.


## Features

- 360° Environment Scanning – Scan your surroundings using the device’s camera and ARKit capabilities.
- Human Body Detection – Recognize people in real time and visualize their body skeleton.
- Hand & Finger Tracking – Detect and render hand and finger movements for gesture-based interaction.
- LiDAR Mode (LiDAR-enabled devices only) –
  * Use the LiDAR sensor for advanced 3D surface mapping.
  * Place 3D virtual objects (currently cubes) on any type of surface — flat or curved.
- SwiftUI + RealityKit Integration – Built entirely with modern Apple frameworks for smooth and immersive AR experiences

## Tech Stack

- Language: Swift
- Frameworks: SwiftUI, ARKit, RealityKit
- Platform: iOS (LiDAR functionality requires a LiDAR-enabled device, e.g. iPad Pro or iPhone Pro models)

## Prerequisites

- Xcode 15 or later
- iOS 18.5 or later
- A device with an A12 Bionic chip or newer (LiDAR features require LiDAR hardware)

## Installation

1. Clone the repository:
```
git clone https://github.com/kv34dev/ARScan360
cd ARScan360
```
2. Open the project in Xcode:
```
open ARScan360.xcodeproj
```
3. Build and run on a real iOS device (AR features won’t work in the simulator).
