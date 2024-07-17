import UIKit
import ARKit

class ARViewController: UIViewController, ARSessionDelegate {
    
    var sceneView: ARSCNView!
    var startStopButton: UIButton!
    var statusLabel: UILabel!
    var currentAverageLabel: UILabel!
    var previousAverageLabel: UILabel!
    var differenceLabel: UILabel!
    var directionLabel: UILabel!
    var isARSessionRunning: Bool = false
    var gridOverlayView: UIView!
    
    var middleSums: [Float32] = []
    var frameCounter: Int = 0
    var threatDistances: [Float32] = []
    var coords: [CGPoint] = []
//    var currentCoord: CGPoint?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView = ARSCNView(frame: self.view.frame)
        self.view.addSubview(sceneView)
        
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            fatalError("LiDAR not supported on this device.")
        }
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = .sceneDepth
        sceneView.session.delegate = self
        
        setupUI()
        setupGridOverlay()
    }
    
    func setupUI() {
        startStopButton = UIButton(type: .system)
        startStopButton.setTitle("Start AR", for: .normal)
        startStopButton.addTarget(self, action: #selector(toggleARSession), for: .touchUpInside)
        startStopButton.frame = CGRect(x: 20, y: view.frame.height - 60, width: 100, height: 40)
        startStopButton.backgroundColor = .white
        startStopButton.layer.cornerRadius = 5
        startStopButton.layer.borderWidth = 1
        startStopButton.layer.borderColor = UIColor.black.cgColor
        view.addSubview(startStopButton)
        
        statusLabel = UILabel(frame: CGRect(x: 20, y: 40, width: view.frame.width - 40, height: 40))
        statusLabel.textAlignment = .center
        statusLabel.textColor = .white
        statusLabel.text = "AR Session Paused"
        view.addSubview(statusLabel)
        
        currentAverageLabel = UILabel(frame: CGRect(x: 20, y: 80, width: view.frame.width - 40, height: 40))
        currentAverageLabel.textAlignment = .center
        currentAverageLabel.textColor = .white
        currentAverageLabel.text = "Current Coordinates: N/A"
        view.addSubview(currentAverageLabel)
        
        previousAverageLabel = UILabel(frame: CGRect(x: 20, y: 120, width: view.frame.width - 40, height: 40))
        previousAverageLabel.textAlignment = .center
        previousAverageLabel.textColor = .white
        previousAverageLabel.text = "Previous Coordinates: N/A"
        view.addSubview(previousAverageLabel)
        
        differenceLabel = UILabel(frame: CGRect(x: 20, y: 160, width: view.frame.width - 40, height: 40))
        differenceLabel.textAlignment = .center
        differenceLabel.textColor = .white
        differenceLabel.text = "Difference: N/A"
        view.addSubview(differenceLabel)
        
        directionLabel = UILabel(frame: CGRect(x: 20, y: 200, width: view.frame.width - 40, height: 40))
        directionLabel.textAlignment = .center
        directionLabel.textColor = .white
        directionLabel.text = "Direction: N/A"
        view.addSubview(directionLabel)
    }
    
    func setupGridOverlay() {
        gridOverlayView = UIView(frame: self.view.frame)
        gridOverlayView.isUserInteractionEnabled = false
        gridOverlayView.backgroundColor = .clear
        
        let gridWidth = gridOverlayView.frame.width / 3
        let gridHeight = gridOverlayView.frame.height / 3
        
        for i in 0...2 {
            for j in 0...2 {
                let gridCell = UIView(frame: CGRect(x: CGFloat(i) * gridWidth, y: CGFloat(j) * gridHeight, width: gridWidth, height: gridHeight))
                gridCell.layer.borderWidth = 1
                gridCell.layer.borderColor = UIColor.red.cgColor
                gridOverlayView.addSubview(gridCell)
            }
        }
        
        view.addSubview(gridOverlayView)
    }
    
    @objc func toggleARSession() {
        if isARSessionRunning {
            sceneView.session.pause()
            startStopButton.setTitle("Start AR", for: .normal)
            statusLabel.text = "AR Session Paused"
        } else {
            startARSession()
            startStopButton.setTitle("Stop AR", for: .normal)
            statusLabel.text = "AR Session Running"
        }
        isARSessionRunning.toggle()
    }
    
    func startARSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = .sceneDepth
        sceneView.session.run(configuration)
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameCounter += 1
        
        if frameCounter % 10 == 0, let sceneDepth = frame.sceneDepth {
            let depthData = sceneDepth.depthMap
            processMiddleDepthData(depthData)
        }
    }
    
    func processMiddleDepthData(_ depthData: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(depthData, .readOnly)
        
        let width = CVPixelBufferGetWidth(depthData)
        let height = CVPixelBufferGetHeight(depthData)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthData) else {
            return
        }
        
        let floatBuffer = unsafeBitCast(baseAddress, to: UnsafeMutablePointer<Float32>.self)
        
        let startX = width / 3
        let endX = 2 * (width / 3)
        let startY = height / 3
        let endY = 2 * (height / 3)
        
        var depthValues: [Float32] = []
        var coordinates: [CGPoint] = []
        
        var depthWithCoordinates: [(depth: Float, coordinate: CGPoint)] = []
        
        for y in startY..<endY {
            for x in startX..<endX {
                let depth = floatBuffer[y * width + x]
//                depthValues.append(depth)
//                coordinates.append(CGPoint(x: x, y: y))
                depthWithCoordinates.append((depth: depth, coordinate: CGPoint(x: x, y: y)))
            }
        }

        CVPixelBufferUnlockBaseAddress(depthData, .readOnly)
        
//        depthValues.sort()
//        let quartileIndex = depthValues.count / 4
//        let d = depthValues[quartileIndex]
        
        depthWithCoordinates.sort { $0.depth < $1.depth }
        let quartileIndex = depthWithCoordinates.count / 4
        let d = depthWithCoordinates[quartileIndex].depth
        let coordinateOfD = depthWithCoordinates[quartileIndex].coordinate
        
        let threshold = d + min(0.5, 0.1 * d)
        
        var closePoints: [(depth: Float32, coord: CGPoint)] = []
        
        for (index, depth) in depthValues.enumerated() {
            if depth <= threshold {
                closePoints.append((depth, coordinates[index]))
                
            }
        }
//        print(closePoints.count)
        
        let threatDistance = closePoints.map { $0.depth }.reduce(0, +) / Float32(closePoints.count)
//        
//        var maxDepth = Float32.leastNormalMagnitude
//        var currentCoord = CGPoint.zero
//        for (depth, coord) in closePoints {
//            if depth < maxDepth {
//                maxDepth = depth
//                currentCoord = coord
//            }
//        }
        var currentCoord = CGPoint.zero
        currentCoord = coordinateOfD
        
        
        if threatDistances.count >= 10 {
            let previousThreatDistance = threatDistances.removeFirst()
            let difference = threatDistance - previousThreatDistance
            differenceLabel.text = "Difference: \(difference)"
            
//            if let previousCoord = previousCoord, let currentCoord = closePoints.first?.coord {
            let previousCoord = coords.removeFirst()
            let direction = currentCoord.x - previousCoord.x
            directionLabel.text = direction < 0 ? "Left" : "Right"
            previousAverageLabel.text = "Previous Coordinates: \(previousCoord)"
            currentAverageLabel.text = "Current Coordinates: \(currentCoord)"
//            }
        }
        
        threatDistances.append(threatDistance)
        coords.append(currentCoord)
    }
}
