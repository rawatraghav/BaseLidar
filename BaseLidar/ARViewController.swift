import UIKit
import ARKit

class ARViewController: UIViewController, ARSessionDelegate {
    
    var sceneView: ARSCNView!
    var startStopButton: UIButton!
    var statusLabel: UILabel!
    var currentAverageLabel: UILabel!
    var previousAverageLabel: UILabel!
    var differenceLabel: UILabel!
    var isARSessionRunning: Bool = false
    var gridOverlayView: UIView!
    
    var middleSums: [Float32] = []
    var frameCounter: Int = 0
    var threatDistances: [Float32] = []
    
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
        
        // Set up the current average label
        currentAverageLabel = UILabel(frame: CGRect(x: 20, y: 80, width: view.frame.width - 40, height: 40))
        currentAverageLabel.textAlignment = .center
        currentAverageLabel.textColor = .white
        currentAverageLabel.text = "Current Average: N/A"
        view.addSubview(currentAverageLabel)
        
        // Set up the previous average label
        previousAverageLabel = UILabel(frame: CGRect(x: 20, y: 120, width: view.frame.width - 40, height: 40))
        previousAverageLabel.textAlignment = .center
        previousAverageLabel.textColor = .white
        previousAverageLabel.text = "Previous Average: N/A"
        view.addSubview(previousAverageLabel)
        
        // Set up the difference label
        differenceLabel = UILabel(frame: CGRect(x: 20, y: 160, width: view.frame.width - 40, height: 40))
        differenceLabel.textAlignment = .center
        differenceLabel.textColor = .white
        differenceLabel.text = "Difference: N/A"
        view.addSubview(differenceLabel)
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
    
    // ARSessionDelegate method to handle new AR frames
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
        
        // Get the base address of the depth data
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthData) else {
            return
        }
        
        let floatBuffer = unsafeBitCast(baseAddress, to: UnsafeMutablePointer<Float32>.self)
        
        // Calculate bounds for the middle part (assuming a 3x3 grid)
        let startX = width / 3
        let endX = 2 * (width / 3)
        let startY = height / 3
        let endY = 2 * (height / 3)
        
        var depthValues: [Float32] = []
        
        // Iterate through the depth data to extract the middle part
        for y in startY..<endY {
            for x in startX..<endX {
                let depth = floatBuffer[y * width + x]
                depthValues.append(depth)
            }
        }

        CVPixelBufferUnlockBaseAddress(depthData, .readOnly)
        
        // Calculate the lowest quartile (25th percentile) value
        depthValues.sort()
        let quartileIndex = depthValues.count / 4
        let d = depthValues[quartileIndex]
        
        // Calculate the threshold distance
        let threshold = d + min(0.5, 0.1 * d)
        
        // Find all points within the threshold distance
        let closePoints = depthValues.filter { $0 <= threshold }
        
        // Calculate the average of the close points
        let threatDistance = closePoints.reduce(0, +) / Float32(closePoints.count)
        
        // Add the threat distance to the array and calculate the difference
        if threatDistances.count >= 10 {
            let previousThreatDistance = threatDistances.removeFirst()
            let difference = threatDistance - previousThreatDistance
            differenceLabel.text = "Difference: \(difference)"
            
            // Change the color of the difference label based on the threshold
            if difference < -1.5 {
                differenceLabel.textColor = .red
            } else {
                differenceLabel.textColor = .white
            }
        }
        
        threatDistances.append(threatDistance)
        
        // Update the UI labels
        previousAverageLabel.text = "Previous Average: \(threatDistances.count > 1 ? threatDistances[threatDistances.count - 2] : threatDistance)"
        currentAverageLabel.text = "Current Average: \(threatDistance)"
    }
}
