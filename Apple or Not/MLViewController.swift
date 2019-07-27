import UIKit
import AVFoundation
import CoreML
import Vision
import ImageIO

class MLViewController: UIViewController {

    // A view to disdplayu the camera preview
    @IBOutlet weak var previewView: UIView!
    
    // The button to take the picture
    @IBOutlet weak var captureButton: UIButton!
    
    // This label will display yes, no, or maybe overlayed over the previewView
    @IBOutlet weak var responseLabel: UILabel!
    
    // Properties for the camera
    var captureSession: AVCaptureSession?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    var capturePhotoOutput: AVCapturePhotoOutput?
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Set the response label to 0. We will change this when Core ML recognizes an apple.
        self.responseLabel.alpha = 0.0
        
        // Check to see if the device can capture video
        guard let captureDevice = AVCaptureDevice.default(for: AVMediaType.video) else {
            fatalError("No vidoe device found")
        }
        
        do {
            // Get an instance of the AVCaptureDeviceInput class using the previous deivce object
            let input = try AVCaptureDeviceInput(device: captureDevice)
            
            // Initialize the captureSession object
            captureSession = AVCaptureSession()
            
            // Set the input devcie on the capture session
            captureSession?.addInput(input)
            
            captureSession?.sessionPreset = .photo
            
            // Get an instance of AVCapturePhotoOutput class
            capturePhotoOutput = AVCapturePhotoOutput()
            capturePhotoOutput?.isHighResolutionCaptureEnabled = true
            
            // Set the output on the capture session
            captureSession?.addOutput(capturePhotoOutput!)
            
            // Initialize a AVCaptureMetadataOutput object and set it as the input device
            let captureMetadataOutput = AVCaptureMetadataOutput()
            captureSession?.addOutput(captureMetadataOutput)
            
            //Initialise the video preview layer and add it as a sublayer to the viewPreview view's layer
            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
            videoPreviewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
            videoPreviewLayer?.contentsGravity = CALayerContentsGravity.resizeAspectFill
            videoPreviewLayer?.frame = previewView.layer.frame//view.layer.bounds
            previewView.layer.addSublayer(videoPreviewLayer!)
            
            //start video capture
            captureSession?.startRunning()
            
        } catch {
            //If any error occurs, simply print it out
            print(error)
            return
        }
       
        
    }
    
    override func viewDidLayoutSubviews() {
        videoPreviewLayer?.frame = previewView.bounds
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    @IBAction func onTapTakePhoto(_ sender: Any) {
        // Make sure capturePhotoOutput is valid
        guard let capturePhotoOutput = self.capturePhotoOutput else { return }
        
        // Get an instance of AVCapturePhotoSettings class
        let photoSettings = AVCapturePhotoSettings()
        
        // Set photo settings for our need
        photoSettings.isAutoStillImageStabilizationEnabled = true
        photoSettings.isHighResolutionPhotoEnabled = true
        photoSettings.flashMode = .auto
        
        // Flash Screen
        let flashView = UIView(frame: view.frame)
        flashView.backgroundColor = .white
        previewView.addSubview(flashView)
        UIView.animate(withDuration: 0.5, animations: {flashView.alpha = 0.0 }, completion: {f in flashView.removeFromSuperview()})
        
        // Call capturePhoto method by passing our photo settings and a delegate implementing AVCapturePhotoCaptureDelegate
        capturePhotoOutput.capturePhoto(with: photoSettings, delegate: self)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        captureSession?.stopRunning()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        captureSession?.startRunning()
    }
    
    // MARK: - Image Classification
    
    /// - Tag: MLModelSetup
    lazy var classificationRequest: VNCoreMLRequest = {
        do {
            
            // MARK: - Change the model here.
            let model = try VNCoreMLModel(for: Fruit().model)

            let request = VNCoreMLRequest(model: model, completionHandler: { [weak self] request, error in
                self?.processClassifications(for: request, error: error)
            })
            request.imageCropAndScaleOption = .centerCrop
            return request
        } catch {
            fatalError("Failed to load Vision ML model: \(error)")
        }
    }()
    
    /// - Tag: PerformRequests
    func updateClassifications(for image: UIImage) {
        //classificationLabel.text = "Classifying..."
        
        let orientation = CGImagePropertyOrientation(rawValue: UInt32(image.imageOrientation.rawValue))
        guard let ciImage = CIImage(image: image) else { fatalError("Unable to create \(CIImage.self) from \(image).") }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(ciImage: ciImage, orientation: orientation ?? CGImagePropertyOrientation.up)
            do {
                try handler.perform([self.classificationRequest])
            } catch {
                /*
                 This handler catches general image processing errors. The `classificationRequest`'s
                 completion handler `processClassifications(_:error:)` catches errors specific
                 to processing that request.
                 */
                print("Failed to perform classification.\n\(error.localizedDescription)")
            }
        }
    }
    
    /// Updates the UI with the results of the classification.
    /// - Tag: ProcessClassifications
    func processClassifications(for request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            guard let results = request.results else {
                //self.classificationLabel.text = "Unable to classify image.\n\(error!.localizedDescription)"
                return
            }
            // The `results` will always be `VNClassificationObservation`s, as specified by the Core ML model in this project.
            let classifications = results as! [VNClassificationObservation]
            
            if classifications.isEmpty {
                self.responseLabel.text = "NO"
                //self.classificationLabel.text = "Nothing recognized."
            } else {
                // Display top classifications ranked by confidence in the UI.
                let topClassifications = classifications.prefix(2)
                _ = topClassifications.map { classification in
                    // Formats the classification for display; e.g. "(0.37) cliff, drop, drop-off".
                    return String(format: "  (%.2f) %@", classification.confidence, classification.identifier)
                }
                
                if topClassifications.first?.identifier == "Apple" {
                    if let confidenceScore = classifications.first?.confidence {
                        print(confidenceScore)
                        self.updateLabel(score: confidenceScore)
                    }
                } else {
                    self.updateLabel(score: 0.0)
                }
            }
        }
    }

    func updateLabel(score: Float) {
        self.responseLabel.alpha = 1.0
        
        if score > 0.98 {
            self.responseLabel.text = "YES"
        } else if score > 0.90 {
            self.responseLabel.text = "MAYBE"
        } else {
            self.responseLabel.text = "NO"
        }
        
        UIView.animate(withDuration: 2.0) {
            self.responseLabel.alpha = 0.0
        }
        
    }

}


extension MLViewController : AVCapturePhotoCaptureDelegate {
    func photoOutput(_ captureOutput: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photoSampleBuffer: CMSampleBuffer?,
                     previewPhoto previewPhotoSampleBuffer: CMSampleBuffer?,
                     resolvedSettings: AVCaptureResolvedPhotoSettings,
                     bracketSettings: AVCaptureBracketedStillImageSettings?,
                     error: Error?) {
        // Make sure we get some photo sample buffer
        guard error == nil,
            let photoSampleBuffer = photoSampleBuffer else {
                print("Error capturing photo: \(String(describing: error))")
                return
        }
        
        // Convert photo same buffer to a jpeg image data by using AVCapturePhotoOutput
        guard let imageData = AVCapturePhotoOutput.jpegPhotoDataRepresentation(forJPEGSampleBuffer: photoSampleBuffer, previewPhotoSampleBuffer: previewPhotoSampleBuffer) else {
            return
        }
        
        // Initialise an UIImage with our image data
        let capturedImage = UIImage.init(data: imageData , scale: 1.0)
        if let image = capturedImage {
            updateClassifications(for: image)
        }
        
    }
}




