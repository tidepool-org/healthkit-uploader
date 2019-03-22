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

class SyncViewController: UIViewController {

    @IBOutlet weak var networkOfflineLabel: UILabel!

    // HK UI...
    @IBOutlet weak var hkEnableSwitch: UISwitch!
    @IBOutlet weak var logOutButton: UIButton!
    @IBOutlet weak var startHistoricalSyncButton: UIButton!
    
    @IBOutlet weak var historicalStateValueLabel: UILabel!
    @IBOutlet weak var currentStateValueLabel: UILabel!
    @IBOutlet weak var currentStateLastUploadLabel: UILabel!
    @IBOutlet weak var currentStateLastTypeValue: UILabel!
    
    @IBOutlet weak var bloodGlucoseHistoricalValue: UILabel!
    @IBOutlet weak var insulinHistoricalValue: UILabel!
    @IBOutlet weak var carbsHistoricalValue: UILabel!
    @IBOutlet weak var workoutsHistoricalLabel: UILabel!

    @IBOutlet weak var bloodGlucoseTotalCnt: UILabel!
    @IBOutlet weak var insulinTotalCnt: UILabel!
    @IBOutlet weak var carbTotalCnt: UILabel!
    @IBOutlet weak var workoutTotalCnt: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.hkUploader = TPUploaderAPI.connector().uploader!
        self.hkUploader.configure()
        configureForReachability()

        hkEnableSwitch.isOn = hkUploader.healthKitInterfaceEnabledForCurrentUser()
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(SyncViewController.handleStatsUpdatedNotification(_:)), name: Notification.Name(rawValue: TPUploaderNotifications.Updated), object: nil)
        notificationCenter.addObserver(self, selector: #selector(SyncViewController.handleTurnOffUploaderNotification(_:)), name: Notification.Name(rawValue: TPUploaderNotifications.TurnOffUploader), object: nil)
        notificationCenter.addObserver(self, selector: #selector(SyncViewController.reachabilityChanged(_:)), name: ReachabilityChangedNotification, object: nil)
        
        historicalProgressLabels["BloodGlucose"] = bloodGlucoseHistoricalValue
        historicalProgressLabels["Insulin"] = insulinHistoricalValue
        historicalProgressLabels["Workout"] = workoutsHistoricalLabel
        historicalProgressLabels["Carb"] = carbsHistoricalValue

        sampleTotalLabels["BloodGlucose"] = bloodGlucoseTotalCnt
        sampleTotalLabels["Insulin"] = insulinTotalCnt
        sampleTotalLabels["Carb"] = carbTotalCnt
        sampleTotalLabels["Workout"] = workoutTotalCnt
    }
    private var hkUploader: TPUploader!
    private var historicalProgressLabels: [String: UILabel] = [:]
    private var sampleTotalLabels: [String: UILabel] = [:]

    @objc func reachabilityChanged(_ note: Notification) {
        DispatchQueue.main.async {
            self.configureForReachability()
        }
    }
    
    func configureForReachability() {
        let connected = APIConnector.connector().isConnectedToNetwork()
        networkOfflineLabel.text = connected ? "Connected to Internet" : "No Internet Connection"
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateCurrentStats()
        updateHistoricalStats()
    }
    
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
        performSegue(withIdentifier: "segueToLogout", sender: self)
    }
    
    @IBAction func startHistoricalSyncButtonHandler(_ sender: Any) {
        // clear any historical progress we persisted...
        hkUploader.startUploading(TPUploader.Mode.HistoricalAll)
    }
    
    //
    // MARK: - Status update
    //
    
    @objc func handleTurnOffUploaderNotification(_ notification: Notification) {
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                
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
        let currentInProgess = hkUploader.isUploadInProgressForMode(TPUploader.Mode.Current)
        currentStateValueLabel.text = currentInProgess ? "in progress" : "stopped"
        currentStateLastUploadLabel.text = " "
        currentStateLastTypeValue.text = " "
        
        var hadSuccessfulUpload = false
        var lastUploadTime = Date.distantPast
        var lastType = " "
        
        let currentStats = hkUploader.currentUploadStats()
        for stat in currentStats {
            if stat.hasSuccessfullyUploaded {
                hadSuccessfulUpload = true
                if stat.lastSuccessfulUploadTime.compare(lastUploadTime) == .orderedDescending {
                    lastUploadTime = stat.lastSuccessfulUploadTime
                    lastType = stat.typeName
                }
                DDLogInfo("Mode: \(stat.mode.rawValue)")
                DDLogInfo("Type: \(stat.typeName)")
                DDLogInfo("Last successful upload time: \(stat.lastSuccessfulUploadTime)")
                DDLogInfo("")
            }
        }
        
        currentStateLastTypeValue.text = lastType
        if hadSuccessfulUpload {
            currentStateLastUploadLabel.text = lastUploadTime.timeAgoInWords(Date())
        }
        
    }
    
    func updateHistoricalStats() {
        DDLogInfo("Historical stats update:")
        let historicInProgess = hkUploader.isUploadInProgressForMode(TPUploader.Mode.HistoricalAll)
        historicalStateValueLabel.text = historicInProgess ? "in progress" : "stopped"
        self.startHistoricalSyncButton.isEnabled = !historicInProgess
        let historicalStats = hkUploader.historicalUploadStats()
        for stat in historicalStats {
            if stat.hasSuccessfullyUploaded {
                DDLogInfo("Mode: \(stat.mode.rawValue)")
                DDLogInfo("Type: \(stat.typeName)")
                DDLogInfo("Current day: \(stat.currentDayHistorical)")
                DDLogInfo("Total days: \(stat.totalDaysHistorical)")
                DDLogInfo("")
            }
            
            if let typeLabel = historicalProgressLabels[stat.typeName] {
                typeLabel.text = "\(stat.currentDayHistorical) of \(stat.totalDaysHistorical)"
            }
            
            if let totalLabel = sampleTotalLabels[stat.typeName] {
                totalLabel.text = "\(stat.totalUploadCount)"
            }
        }
    }

}

