/*
 * Copyright (c) 2019, Tidepool Project
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

import Foundation

func DDLogVerbose(_ str: String) { TPUploader.sharedInstance?.config.logVerbose(str) }
func DDLogInfo(_ str: String) { TPUploader.sharedInstance?.config.logInfo(str) }
func DDLogDebug(_ str: String) { TPUploader.sharedInstance?.config.logDebug(str) }
func DDLogError(_ str: String) { TPUploader.sharedInstance?.config.logError(str) }

public class TPUploader {
    
    /// Nil if not instance not configured yet...
    static var sharedInstance: TPUploader? 
    
    /// Configures framework
    public init(_ config: TPUploaderConfigInfo) {
        DDLogInfo("\(#function)")
        // TODO: fail if already configured! Should probably just have the init private, and provide access via a connector() method like other singletons that require initialization data.
        self.config = config
        self.service = TPUploaderServiceAPI(config)
        // configure this last, it might use the service to send up an initial timezone...
        self.tzTracker = TPTimeZoneTracker()
        // TODO: allow this to be passed in as array of enums!
        _ = HealthKitConfiguration.init(config, healthKitUploadTypes: [
            HealthKitUploadTypeBloodGlucose(),
            HealthKitUploadTypeCarb(),
            HealthKitUploadTypeInsulin(),
            HealthKitUploadTypeWorkout(),
            ])
        TPUploader.sharedInstance = self
    }
    var config: TPUploaderConfigInfo
    var service: TPUploaderServiceAPI
    var tzTracker: TPTimeZoneTracker
    
    //
    // MARK: - misc methods
    //
    
    /// Call this whenever the current user changes, after login/logout, token refresh(?), ...
    public func configure() {
        HealthKitConfiguration.sharedInstance.configureHealthKitInterface()
    }
    
    /// Does this device support HealthKit and is current logged in user account a DSA account?
    public func shouldShowHealthKitUI() -> Bool {
        //DDLogVerbose("\(#function)")
        return HealthKitManager.sharedInstance.isHealthDataAvailable && config.isDSAUser()
    }

    /// Disables HealthKit for current user
    ///
    /// Note: This does not NOT clear the current HealthKit user!
    public func disableHealthKitInterface() {
        DDLogInfo("\(#function)")
        HealthKitConfiguration.sharedInstance.disableHealthKitInterface()
        // clear uploadId to be safe... also for logout.
        TPUploaderServiceAPI.connector!.currentUploadId = nil
    }

    /// Enable HealthKit for current user.
    ///
    /// Note: This will force switch of HK user if necessary!
    public func enableHealthKitInterface() {
        DDLogInfo("\(#function)")
        HealthKitConfiguration.sharedInstance.enableHealthKitInterface()
    }

    /// Returns true only if the HealthKit interface is enabled and configured for the current user
    public func healthKitInterfaceEnabledForCurrentUser() -> Bool {
        DDLogInfo("\(#function)")
        return HealthKitConfiguration.sharedInstance.healthKitInterfaceEnabledForCurrentUser()
    }
    
    /// Returns true if the HealthKit interface has been configured for a tidepool id different from the current user - ignores whether the interface is currently enabled.
    public func healthKitInterfaceConfiguredForOtherUser() -> Bool {
        DDLogInfo("\(#function)")
        return HealthKitConfiguration.sharedInstance.healthKitInterfaceConfiguredForOtherUser()
    }

    public func curHKUserName() -> String? {
        return HealthKitConfiguration.sharedInstance.healthKitUserTidepoolUsername()
    }
}
