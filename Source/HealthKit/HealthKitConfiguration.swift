/*
 * Copyright (c) 2018, Tidepool Project
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the associated License, which is identical to the BSD 2-Clause
 * License as published by the Open Source Initiative at opensource.org.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the License for more details.
 *
 * You should have received a copy of the License along with this program; if
 * not, you can obtain one from Tidepool Project at tidepool.org.
 */

import HealthKit

class HealthKitConfiguration
{
    static var sharedInstance: HealthKitConfiguration!
    init(_ config: TPUploaderConfigInfo, healthKitUploadTypes: [HealthKitUploadType]) {
        self.healthKitUploadTypes = healthKitUploadTypes
        self.config = config
        HealthKitConfiguration.sharedInstance = self
    }

    let settings = HKGlobalSettings.sharedInstance
    
    // MARK: Access, availability, authorization

    private(set) var config: TPUploaderConfigInfo
    private(set) var healthKitUploadTypes: [HealthKitUploadType]
    
    /// Call this whenever the current user changes, at login/logout, token refresh(?), and upon enabling or disabling the HealthKit interface.
    func configureHealthKitInterface() {
        configureHealthKitInterface(shouldAuthorize: true)
    }
    private(set) var turningOnHKInterface = false
    private(set) var isInterfaceOn = false

    private func configureHealthKitInterface(shouldAuthorize: Bool) {
        DDLogVerbose("\(#function), shouldAuthorize: \(shouldAuthorize)")

        if !HealthKitManager.sharedInstance.isHealthDataAvailable {
            DDLogInfo("HKHealthStore data is not available")
            return
        }

        var interfaceEnabled = true
        if config.currentUserId() != nil  {
            interfaceEnabled = isHealthKitInterfaceEnabledForCurrentUser()
            if !interfaceEnabled {
                DDLogInfo("disable because not enabled for current user!")
            } else {
              DDLogInfo("enable because enabled for current user!")
          }
        } else {
            interfaceEnabled = false
            DDLogInfo("disable because no current user!")
        }
        
        if interfaceEnabled && !isInterfaceOn {
            DDLogInfo("enable!")
                    
            if turningOnHKInterface {
                DDLogError("Ignoring turn on HK interface, already in progress!")
                return
            }
            // set flag to prevent reentrancy!
            turningOnHKInterface = true
            DDLogInfo("Turning on HK interface")
            self.settings.interfaceTurnedOffError.value = ""
            config.onTurningOnInterface()

            if shouldAuthorize {
                authorizeHealthKit()
                if !HealthKitManager.sharedInstance.isHealthKitAuthorized {
                  interfaceEnabled = false
                  DDLogInfo("disable because HealthKit not authorized!")
                }
            }
        }
      
        if interfaceEnabled {
            TPUploaderServiceAPI.connector?.configureUploadId() { (error) in
                // If we are still turning on the HK interface after fetch of upload id, continue!
                if self.turningOnHKInterface {
                    DDLogInfo("No longer turning on HK interface")
                    self.turningOnHKInterface = false
                    if TPUploaderServiceAPI.connector?.currentUploadId != nil {
                        self.turnOnInterface()
                    } else {
                        // TODO: uploader - If we fail to turn on interface then do a retry up to n (configurable) times. If it still fails, some sort of error to user, both in sidebar, and in sync UI, with option to trap to retry. Also, when tapping, maybe actually show the real error?
                        self.turnOffInterface(error)
                    }
                }
            }
        } else {
            DDLogInfo("disable!")
            turningOnHKInterface = false
            self.turnOffInterface(nil)
        }
    }

    /// Turn on HK interface: start/resume uploading if possible...
    private func turnOnInterface() {
        DDLogVerbose("\(#function)")

        guard !self.isInterfaceOn else {
            DDLogInfo("Interface already on, ignoring")
            return
        }
      
        self.isInterfaceOn = true
        self.settings.interfaceTurnedOffError.value = ""
        config.onTurnOnInterface();

        let hkManager = HealthKitUploadManager.sharedInstance
        if config.currentUserId() != nil {
            // Always start uploading TPUploader.Mode.Current samples when interface is turned on
            hkManager.startUploading(mode: TPUploader.Mode.Current, config: config)

            let state = UIApplication.shared.applicationState
            if state != .background {
                // Resume uploading historical
                hkManager.resumeUploadingIfResumableOrPending(mode: .HistoricalAll, config: config)

                // Really just a one-time check to upload biological sex if Tidepool does not have it, but we can get it from HealthKit.
                TPUploaderServiceAPI.connector?.updateProfileBioSexCheck()
            }
        
        } else {
            DDLogInfo("No logged in user, unable to start uploading")
        }
    }

    private func turnOffInterface(_ error: Error?) {
        DDLogVerbose("\(#function)")

        self.isInterfaceOn = false
        self.settings.interfaceTurnedOffError.value = error?.localizedDescription ?? ""
        config.onTurnOffInterface(error);
        HealthKitUploadManager.sharedInstance.stopUploading(reason: TPUploader.StoppedReason.interfaceTurnedOff)
    }

    //
    // MARK: - Methods needed for config UI
    //    
    
    /// Enables HealthKit for current user, and authorizes HealthKit data
    ///
    /// Note: This sets the current tidepool user as the HealthKit user, and authorizes HealthKit data
    func enableHealthKitInterfaceAndAuthorize() {
        
        DDLogVerbose("\(#function)")
        
        guard self.config.currentUserId() != nil else {
            DDLogError("No logged in user at enableHealthKitInterfaceAndAuthorize!")
            return
        }
      
        let username = self.config.currentUserName

        if !self.isHealthKitInterfaceEnabledForCurrentUser() {
            if self.isHealthKitInterfaceConfiguredForOtherUser() {
                // Switching healthkit users, reset HealthKitUploadManager
                HealthKitUploadManager.sharedInstance.resetPersistentState(switchingHealthKitUsers: true)
                // Also clear any persisted timezone data so an initial tz reading will be sent for this new user
                TPTimeZoneTracker.tracker?.clearTzCache()
            }
            // force refetch of upload id because it may have changed for the new user...
            TPUploaderServiceAPI.connector?.currentUploadId = nil
            settings.interfaceUserId.value = config.currentUserId()!
            settings.interfaceUserName.value = username
        }
        // Note: set this at the end because above will clear this value if switching current HK user!
        settings.interfaceEnabled.value = true
      
        authorizeHealthKit()
    }

    /// Authorizes HealthKit for current user
    func authorizeHealthKit() {
        DDLogVerbose("\(#function)")
        
        guard self.config.currentUserId() != nil else {
            DDLogError("No logged in user at authorizeHealthKit!")
            return
        }
      
        guard self.settings.interfaceEnabled.value else {
          DDLogError("Interface not enabled at authorizeHealthKit!")
          return
        }

        HealthKitManager.sharedInstance.authorize() {
            success, error -> Void in
            
            DDLogVerbose("\(#function)")

            if success {
                // NOTE: This doesn't mean user gave access, just that the authorization was presented
                DDLogError("Success authorizing health data")
                DispatchQueue.main.async(execute: {
                  self.configureHealthKitInterface(shouldAuthorize: false)
                })
            } else if error != nil {
                DDLogError("Error authorizing health data \(String(describing: error)), \(error!.userInfo)")
            } else {
                DDLogError("Unknown error authorizing health data")
            }
        }
    }

    /// Disables HealthKit for current user
    ///
    /// Note: This does NOT clear the current HealthKit user!
    func disableHealthKitInterface() {
        DDLogVerbose("\(#function)")
        settings.interfaceEnabled.value = false
        configureHealthKitInterface(shouldAuthorize: false)
    }

    /// Returns true only if the HealthKit interface is enabled and configured for the current user
    func isHealthKitInterfaceEnabledForCurrentUser() -> Bool {
        if healthKitInterfaceEnabled() == false {
            return false
        }
        if let curHealthKitUserId = healthKitUserTidepoolId(), let curId = config.currentUserId() {
            if curId == curHealthKitUserId {
                return true
            }
        }
        return false
    }

    /// Returns true if the HealthKit interface has been configured for a tidepool id different from the current user - ignores whether the interface is currently enabled.
    func isHealthKitInterfaceConfiguredForOtherUser() -> Bool {
        if let curHealthKitUserId = healthKitUserTidepoolId() {
            if let curId = config.currentUserId() {
                if curId != curHealthKitUserId {
                    return true
                }
            } else {
                DDLogError("No logged in user at isHealthKitInterfaceConfiguredForOtherUser!")
                return true
            }
        }
        return false
    }
    
    /// Returns whether authorization for HealthKit has been requested, and the HealthKit interface is currently enabled, regardless of user it is enabled for.
    ///
    /// Note: separately, we may enable/disable the current interface to HealthKit.
    fileprivate func healthKitInterfaceEnabled() -> Bool {
        return settings.interfaceEnabled.value
    }
    
    /// If HealthKit interface is enabled, returns associated Tidepool account id
    func healthKitUserTidepoolId() -> String? {
        return settings.interfaceUserId.value
    }

    /// If HealthKit interface is enabled, returns associated Tidepool account id
    func healthKitUserTidepoolUsername() -> String? {
        return settings.interfaceUserName.value
    }
}
