//
//  ViewController.swift
//  UploaderTester
//
//  Created by Larry Kenyon on 2/20/19.
//  Copyright © 2019 Tidepool. All rights reserved.
//

import UIKit
import CocoaLumberjack
import Alamofire
import SwiftyJSON
import TPHealthKitUploader

class LoginViewController: UIViewController {

    @IBOutlet weak var inputContainerView: UIView!
    
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var passwordTextField: UITextField!
    @IBOutlet weak var loginButton: UIButton!
    @IBOutlet weak var errorFeedbackLabel: UILabel!
    @IBOutlet weak var serviceButton: UIButton!
    @IBOutlet weak var loginIndicator: UIActivityIndicatorView!
    @IBOutlet weak var networkOfflineLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        hkUploader = TPUploaderAPI.connector().uploader!
        configureForReachability()
        updateButtonStates()
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(LoginViewController.textFieldDidChange), name: UITextField.textDidChangeNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(LoginViewController.reachabilityChanged(_:)), name: ReachabilityChangedNotification, object: nil)
      self.serviceButton.setTitle(APIConnector.connector().currentService, for: .normal)
    }
    private var hkUploader: TPUploader!
    
    static var firstTime = true
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if LoginViewController.firstTime {
            LoginViewController.firstTime = false
            if APIConnector.connector().sessionToken != nil && APIConnector.connector().isConnectedToNetwork() {
                performSegue(withIdentifier: "segueToSyncVC", sender: self)
            }
        }
    }
    
    @objc func reachabilityChanged(_ note: Notification) {
        DispatchQueue.main.async {
            self.configureForReachability()
        }
    }

    func configureForReachability() {
        let connected = APIConnector.connector().isConnectedToNetwork()
        networkOfflineLabel.text = connected ? "Connected to Internet" : "No Internet Connection"
    }

    //
    // MARK: - Segues
    //

    @IBAction func logout(_ segue: UIStoryboardSegue) {
        DDLogInfo("unwind segue to login view controller!")
        if APIConnector.connector().sessionToken != nil {
            APIConnector.connector().logout()
            hkUploader.configure()
        }
    }

    //
    // MARK: - Login
    //
    
    @IBAction func tapOutsideFieldHandler(_ sender: AnyObject) {
        passwordTextField.resignFirstResponder()
        emailTextField.resignFirstResponder()
    }
    
    @IBAction func passwordEnterHandler(_ sender: AnyObject) {
        passwordTextField.resignFirstResponder()
        if (loginButton.isEnabled) {
            login_button_tapped(self)
        }
    }
    
    @IBAction func emailEnterHandler(_ sender: AnyObject) {
        passwordTextField.becomeFirstResponder()
    }
    
    @IBAction func login_button_tapped(_ sender: AnyObject) {
        updateButtonStates()
        tapOutsideFieldHandler(self)
        loginIndicator.startAnimating()
        
        APIConnector.connector().login(emailTextField.text!, password: passwordTextField.text!) {
            (result:Alamofire.Result<[String: Any?]>, statusCode: Int?) -> (Void) in
            DDLogInfo("Login result: \(result)")
            self.processLoginResult(result, statusCode: statusCode)
        }
    }
    
    fileprivate func processLoginResult(_ result: Alamofire.Result<[String: Any?]>, statusCode: Int?) {
        self.loginIndicator.stopAnimating()
        if (result.isSuccess) {
            if let user=result.value {
                DDLogInfo("Login success: \(user)")
                performSegue(withIdentifier: "segueToSyncVC", sender: self)
            } else {
                // This should not happen- we should not succeed without a user!
                DDLogError("Fatal error: No user returned!")
            }
        } else {
            DDLogError("login failed! Error: " + result.error.debugDescription)
            var errorText = "Check your Internet connection!"
            if let statusCode = statusCode {
                if statusCode == 401 {
                    errorText = "Wrong email or password!"
                }
            }
            self.errorFeedbackLabel.text = errorText
            self.errorFeedbackLabel.isHidden = false
            //self.passwordTextField.text = ""
        }
    }
    
    @objc func textFieldDidChange() {
        updateButtonStates()
    }
    
    private func updateButtonStates() {
        errorFeedbackLabel.isHidden = true
        let connected = APIConnector.connector().isConnectedToNetwork()
        // login button
        if (emailTextField.text != "" && passwordTextField.text != "" && connected) {
            loginButton.isEnabled = true
            loginButton.setTitleColor(UIColor.black, for:UIControl.State())
        } else {
            loginButton.isEnabled = false
            loginButton.setTitleColor(UIColor.lightGray, for:UIControl.State())
        }
    }
    
    @IBAction func selectServiceButtonHandler(_ sender: Any) {
        let api = APIConnector.connector()
        let actionSheet = UIAlertController(title: "Server" + " (" + api.currentService! + ")", message: "", preferredStyle: .actionSheet)
        for serverName in api.kSortedServerNames {
            actionSheet.addAction(UIAlertAction(title: serverName, style: .default, handler: { Void in
                api.switchToServer(serverName)
                self.serviceButton.setTitle(api.currentService, for: .normal)
            }))
        }
        self.present(actionSheet, animated: true, completion: nil)
    }

}

