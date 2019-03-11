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

class ViewController: UIViewController {

    @IBOutlet weak var loginViewContainer: UIControl!
    @IBOutlet weak var inputContainerView: UIView!
    
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var passwordTextField: UITextField!
    @IBOutlet weak var loginButton: UIButton!
    @IBOutlet weak var errorFeedbackLabel: UILabel!
    @IBOutlet weak var serviceButton: UIButton!
    @IBOutlet weak var loginIndicator: UIActivityIndicatorView!
    @IBOutlet weak var networkOfflineLabel: UILabel!

    // HK UI...
    @IBOutlet weak var runViewContainer: UIView!
    @IBOutlet weak var hkEnableSwitch: UISwitch!
    @IBOutlet weak var logOutButton: UIButton!
    @IBOutlet weak var startHistoricalSyncButton: UIButton!
        
    override func viewDidLoad() {
        super.viewDidLoad()
        hkUploader = TPUploaderAPI.connector().uploader!
        
        // Do any additional setup after loading the view, typically from a nib.
        self.configureAsLoggedIn(APIConnector.connector().sessionToken != nil)
        updateButtonStates()
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(ViewController.textFieldDidChange), name: UITextField.textDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.handleStatsUpdatedNotification(_:)), name: Notification.Name(rawValue: TPUploaderNotifications.Updated), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.handleTurnOffUploaderNotification(_:)), name: Notification.Name(rawValue: TPUploaderNotifications.TurnOffUploader), object: nil)
      self.serviceButton.setTitle(APIConnector.connector().currentService, for: .normal)
    }
    private var hkUploader: TPUploader!
    
    //
    // MARK: - HealthKit UI
    //
    
    @IBAction func hkEnableSwitchChanged(_ sender: Any) {
        if hkEnableSwitch.isOn {
            if hkUploader.healthKitInterfaceConfiguredForOtherUser() {
                // use dialog to confirm delete with user!
                let curHKUserName = hkUploader.curHKUserName() ?? ""
                let titleString = "Are you sure?"
                let messageString = "A different account (" + curHKUserName + ") is currently associated with Health Data on this device"
                let alert = UIAlertController(title: titleString, message: messageString, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { Void in
                    self.hkEnableSwitch.isOn = false
                    return
                }))
                alert.addAction(UIAlertAction(title: "Change Account", style: .default, handler: { Void in
                    self.hkUploader.enableHealthKitInterface()
                }))
                self.present(alert, animated: true, completion: nil)

            } else {
                hkUploader.enableHealthKitInterface()
            }
        } else {
            hkUploader.disableHealthKitInterface()
        }
    }
    
    @IBAction func logout_button_tapped(_ sender: AnyObject) {
        APIConnector.connector().logout()
        hkUploader.configure()
        updateButtonStates()
        self.configureAsLoggedIn(false)
    }
    
    //
    // MARK: - Status update
    //
    
    @objc func handleTurnOffUploaderNotification(_ notification: Notification) {
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                //let mode = notification.object as! HealthKitUploadReader.Mode
                let userInfo = notification.userInfo!
                let mode = userInfo["mode"] as! TPUploader.Mode
                let type = userInfo["type"] as! String
                let reason = userInfo["reason"] as! TPUploader.StoppedReason
                DDLogInfo("Type: \(type), Mode: \(mode), Reason: \(reason)")
                if mode == TPUploader.Mode.HistoricalAll {
                    // Update status
                    switch reason {
                    case .turnOffInterface:
                        break
                    case .noResultsFromQuery:
                        DDLogInfo("TODO: self.checkForComplete")
                        //self.checkForComplete()
                        break
                    case .error(let error):
                        self.lastErrorString = String("\(type) upload error: \(error.localizedDescription.prefix(50))")
                        DDLogInfo("TODO: set error, self.checkForComplete")
                        //self.healthStatusLine2.text = self.lastErrorString
                        //self.checkForComplete()
                        break
                    default:
                        break
                    }
                }

            }
        }
    }
    private var lastErrorString: String?
    
    @objc func handleStatsUpdatedNotification(_ notification: Notification) {
        DispatchQueue.main.async {
            //let mode = notification.object as! HealthKitUploadReader.Mode
            let userInfo = notification.userInfo!
            let mode = userInfo["mode"] as! TPUploader.Mode
            let type = userInfo["type"] as! String
            DDLogInfo("Type: \(type), Mode: \(mode)")
            if mode == TPUploader.Mode.HistoricalAll {
                self.updateHistoricalStats()
            } else {
                self.updateCurrentStats()
            }
        }
    }

    func updateCurrentStats() {
        DDLogInfo("Current stats update:")
        let currentStats = hkUploader.currentUploadStats()
        for stat in currentStats {
            if stat.hasSuccessfullyUploaded {
                DDLogInfo("Mode: \(stat.mode.rawValue)")
                DDLogInfo("Type: \(stat.typeName)")
                DDLogInfo("Last successful upload time: \(stat.lastSuccessfulUploadTime)")
                DDLogInfo("")
            }
        }
    }
    
    func updateHistoricalStats() {
        DDLogInfo("Historical stats update:")
        let historicalStats = hkUploader.historicalUploadStats()
        for stat in historicalStats {
            if stat.hasSuccessfullyUploaded {
                DDLogInfo("Mode: \(stat.mode.rawValue)")
                DDLogInfo("Type: \(stat.typeName)")
                DDLogInfo("Current day: \(stat.currentDayHistorical)")
                DDLogInfo("Total days: \(stat.totalDaysHistorical)")
                DDLogInfo("")
            }
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
                self.hkUploader.configure()
                self.configureAsLoggedIn(true)
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
    
    private func configureAsLoggedIn(_ loggedIn: Bool) {
        runViewContainer.isHidden = !loggedIn
        loginViewContainer.isHidden = loggedIn
        networkOfflineLabel.text = loggedIn ? "Online" : "Offline"
        if loggedIn {
            hkEnableSwitch.isOn = hkUploader.healthKitInterfaceEnabledForCurrentUser()
        }
    }
    
    private func updateButtonStates() {
        errorFeedbackLabel.isHidden = true
        // login button
        if (emailTextField.text != "" && passwordTextField.text != "") {
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

