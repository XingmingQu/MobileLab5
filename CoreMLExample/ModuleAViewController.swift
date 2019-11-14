//
//  ViewController.swift
//  CoreMLExample
//
//  Created by Eric Larson on 9/5/17.
//  Copyright © 2017 Eric Larson. All rights reserved.
//
import UIKit
import CoreML
import Vision
import CoreImage
import Accelerate

//let SERVER_URL = "http://10.8.107.62:8000" // change this for your server name!!!

class ModuleAViewController: UIViewController, UINavigationControllerDelegate,UITextFieldDelegate,URLSessionDelegate {
    
    //MARK: UI View Elements
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var dsidLabel: UILabel!
    @IBOutlet weak var NameTextField: UITextField!
    @IBOutlet weak var URLtextField: UITextField!
    @IBOutlet weak var mainImageView: UIImageView!
    @IBOutlet weak var classifierLabel: UILabel!
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {   //delegate method
      textField.resignFirstResponder()
      return true
    }
    var SERVER_URL = "192.168.1.7" {
        didSet{
            DispatchQueue.main.async{
                // update label when set
                
                self.URLtextField.text = (self.SERVER_URL)
            }
        }
    }
    let mytool = tools()
    let operationQueue = OperationQueue()
    var session = URLSession()
    let animation = CATransition()
    var dsid:Int = 0 {
        didSet{
            DispatchQueue.main.async{
                // update label when set
                self.dsidLabel.layer.add(self.animation, forKey: nil)
                self.dsidLabel.text = "Current DSID: \(self.dsid)"
            }
        }
    }
    @IBAction func uploadImage(_ sender: UIButton) {
        let result = sendFeatures(mainImageView.image!, withLabel: NameTextField.text!)
        sleep(1)
        if result == 0{
            statusLabel.text = "Upload Success!"
            statusLabel.isHidden = false
            mainImageView.image =  UIImage(named: "ok")
            
        }
    }
    
    //MARK: Comm with Server
    func sendFeatures(_ image:UIImage, withLabel label:String) -> (Int){
        let targetURL = "http://\(self.URLtextField.text!):8000"
        let baseURL = "\(targetURL)/AddDataPoint"
        let postUrl = URL(string: "\(baseURL)")
        
        // create a custom HTTP POST request
        var request = URLRequest(url: postUrl!)
        
        // data to send in body of post request (send arguments as json)
        let jpegData = UIImageJPEGRepresentation(image, 1.0)
        let encodedString = jpegData?.base64EncodedString()
//        print(image.size.width)
        let jsonUpload:NSDictionary = ["feature":encodedString!,
                                       "label":"\(label)",
                                       "dsid":self.dsid]
        
        
        let requestBody:Data? = self.mytool.convertDictionaryToData(with:jsonUpload)
        
        request.httpMethod = "POST"
        request.httpBody = requestBody

        let postTask : URLSessionDataTask = self.session.dataTask(with: request,
            completionHandler:{(data, response, error) in
                if(error != nil){
                    if let res = response{
                        print("Response:\n",res)
                    }
                }
                else{
                    let jsonDictionary = self.mytool.convertDataToDictionary(with: data)
                    
//                    print(jsonDictionary["feature"]!)
                    print(jsonDictionary["label"]!)
                    
                }

        })
        
        postTask.resume() // start the task

        return 0
    }
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NameTextField.delegate = self
        // Do any additional setup after loading the view, typically from a nib.
        dsid = 1
        URLtextField.text = "192.168.1.7"
        let sessionConfig = URLSessionConfiguration.ephemeral
        statusLabel.isHidden = true
        sessionConfig.timeoutIntervalForRequest = 5.0
        sessionConfig.timeoutIntervalForResource = 8.0
        sessionConfig.httpMaximumConnectionsPerHost = 1
        
        self.session = URLSession(configuration: sessionConfig,
            delegate: self,
            delegateQueue:self.operationQueue)
    }
    
    //MARK: ML Model Load
    // Load an image classifier and encapsulate in the Vision model class
    lazy var model: VNCoreMLModel? = {
        guard let tmpModel = try? VNCoreMLModel(for: GoogLeNetPlaces().model) else {
            return nil
        }
       return tmpModel
    }()
    
    //MARK: Camera View Presentation
    @IBAction func takePicture(_ sender: UIButton) {
        
        if !UIImagePickerController.isSourceTypeAvailable(.camera) {
            return
        }
        
        let cameraPicker = UIImagePickerController()
        cameraPicker.delegate = (self as UIImagePickerControllerDelegate & UINavigationControllerDelegate)
        cameraPicker.sourceType = .camera
        cameraPicker.allowsEditing = false
        present(cameraPicker, animated: true)
    }
}

extension ModuleAViewController: UIImagePickerControllerDelegate {
    
    //MARK: Camera View Callbacks
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismiss(animated: true, completion: nil)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        picker.dismiss(animated: true)
        guard let image = info["UIImagePickerControllerOriginalImage"] as? UIImage else {
            return
        }
        
//        let newImage = classifyImage(image: image)
        let targetSize = CGSize(width: 300, height: 400)
        let resizedImg = self.mytool.resize(image: image, targetSize: targetSize)
        mainImageView.image = resizedImg
//        print(resizedImg.size.width)
    }
    

    
    //MARK: Custom Classification Methods
    // use vision API to classify image
    func classifyImage(image:UIImage) -> (UIImage){
        // Todo: is there anything we can try to make this more accurate?
        // Perhaps: -crop image so it isn't squashed
        //          -increase contrast
        //          -add some blurring/noise filters
        
        
        var cgImage: CGImage? = nil
        
        // try to apply a cropping filter
        var ciImage = CIImage(cgImage: image.cgImage!)
        let filter = CIFilter(name:"CICrop")
        filter?.setValue(CIVector(x: 0, y: 0, z: 224, w: 224), forKey: "inputRectangle")
        filter?.setValue(ciImage, forKey: "inputImage")
        ciImage = (filter?.outputImage)!

        cgImage = ciImage.cgImage
        
        if cgImage == nil{
            cgImage = image.cgImage
        }
        
        // generate request for vision and ML model
        let request = VNCoreMLRequest(model: self.model!, completionHandler: resultsMethod)
        
        // add data to vision request handler
        let handler = VNImageRequestHandler(cgImage: cgImage!, options: [:])
        
        // now perform classification
        do{
            try handler.perform([request])
        }catch _{
            self.classifierLabel.text = "Error, could not classify"
        }
        
        // todo return the UIIMage for display
        return UIImage(cgImage: cgImage!, scale: image.scale, orientation: image.imageOrientation)
    }
    
    //interpret results from vision query
    func resultsMethod(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNClassificationObservation]
            else {
                fatalError("Could not cast request as classification object")
        }
        
        // Add in results display...
        print("---------------")
        for result in results {
            if(result.confidence > 0.05){
                print(result.identifier,result.confidence)
            }
        }
        
        DispatchQueue.main.async{
            self.classifierLabel.text = "This might be a \(results[0].identifier) \n conf:\(results[0].confidence)"
            
        }
        
    }
    

}

