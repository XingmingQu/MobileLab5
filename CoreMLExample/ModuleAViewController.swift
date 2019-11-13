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
class ModuleAViewController: UIViewController, UINavigationControllerDelegate,UITextFieldDelegate {
    
    //MARK: UI View Elements
    @IBOutlet weak var dsidLabel: UILabel!
    @IBOutlet weak var NameTextField: UITextField!
    @IBOutlet weak var mainImageView: UIImageView!
    @IBOutlet weak var classifierLabel: UILabel!
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {   //delegate method
      textField.resignFirstResponder()
      return true
    }
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
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NameTextField.delegate = self
        // Do any additional setup after loading the view, typically from a nib.
        dsid = 1
    }
    
    //MARK: ML Model Load
    // Load an image classifier and encapsulate in the Vision model class
    lazy var model: VNCoreMLModel? = {
        guard let tmpModel = try? VNCoreMLModel(for: GoogLeNetPlaces().model) else {
            return nil
        }
       return tmpModel
    }()
    
    // select some different classification models!
    @IBAction func modelSelectChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            guard let tmpModel = try? VNCoreMLModel(for: GoogLeNetPlaces().model) else {
                return
            }
            model = tmpModel
        case 1:
            guard let tmpModel = try? VNCoreMLModel(for: SqueezeNet().model) else {
                return
            }
            model = tmpModel
        case 2:
            guard let tmpModel = try? VNCoreMLModel(for: Resnet50().model) else {
                return
            }
            model = tmpModel
        default:
            return
        }
        // update UI if we changed and an image exists
        if let image = self.mainImageView.image {
            classifyImage(image: image)
        }
    }
    
    
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
        
        let newImage = classifyImage(image: image)
        let targetSize = CGSize(width: 300, height: 400)
        let resizedImg = resize(image: newImage, targetSize: targetSize)
        mainImageView.image = resizedImg
    }
    
    //https://gist.github.com/marcosgriselli/00ab6c68f48ccaeb110afc82786767ec
    func resize(image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        
        let widthRatio  = targetSize.width  / image.size.width
        let heightRatio = targetSize.height / image.size.height
        
        var newSize: CGSize
        if widthRatio > heightRatio {
            newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        } else {
            newSize = CGSize(width: size.width * widthRatio,  height: size.height * widthRatio)
        }
        
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage!
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

