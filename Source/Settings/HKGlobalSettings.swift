//
//  HKGlobalSettings.swift
//  TPHealthKitUploader
//
//  Created by Larry Kenyon on 4/8/19.
//  Copyright © 2019 Tidepool. All rights reserved.
//

import Foundation

class HKGlobalSettings {
    static let sharedInstance = HKGlobalSettings()

    // General interface settings
    var interfaceEnabled: HKSettingBool
    var interfaceUserId: HKSettingString
    var interfaceUserName: HKSettingString
    var hkDataUploadId: HKSettingString
    var lastExecutedUploaderVersion: HKSettingInt
    var hasPresentedSyncUI: HKSettingBool
  
    // Other upload settings
    var historicalEndDate: HKSettingDate
    var historicalEarliestDate: HKSettingDate
    var historicalLatestDate: HKSettingDate
    var hasPendingHistoricalUploads: HKSettingBool
    var currentStartDate: HKSettingDate
    var hasPendingCurrentUploads: HKSettingBool
    var lastSuccessfulCurrentUploadTime: HKSettingDate
    var currentUploadEarliestSampleTime: HKSettingDate
    var currentUploadLatestSampleTime: HKSettingDate
    var currentTotalSamplesUploadCount: HKSettingInt
    var currentTotalDeletesUploadCount: HKSettingInt
    var historicalTotalSamplesUploadCount: HKSettingInt
    var historicalTotalDeletesUploadCount: HKSettingInt
    var historicalTotalDays: HKSettingInt
    var historicalCurrentDay: HKSettingInt
    var historicalUploadEarliestSampleTime: HKSettingDate
    var historicalUploadLatestSampleTime: HKSettingDate
    var historicalIsResumable: HKSettingBool

    func currentProgress() -> TPUploaderGlobalStats {
        return TPUploaderGlobalStats(lastUpload: lastSuccessfulCurrentUploadTime.value, totalHistDays: historicalTotalDays.value, currentHistDay: historicalCurrentDay.value, totalHistSamples: historicalTotalSamplesUploadCount.value, totalHistDeletes: historicalTotalDeletesUploadCount.value, totalCurSamples: currentTotalSamplesUploadCount.value, totalCurDeletes: currentTotalDeletesUploadCount.value, currentUploadEarliestSampleTime: currentUploadEarliestSampleTime.value, currentUploadLatestSampleTime: currentUploadLatestSampleTime.value, currentStartDate: currentStartDate.value, historicalUploadEarliestSampleTime: historicalUploadEarliestSampleTime.value, historicalUploadLatestSampleTime: historicalUploadLatestSampleTime.value)
    }
    
    func resetAll() {
        DDLogVerbose("HKGlobalSettings")
        for setting in userSettings {
            setting.reset()
        }
        self.resetHistoricalUploadSettings()
        self.resetCurrentUploadSettings()
    }

    func resetHistoricalUploadSettings() {
        DDLogVerbose("HKGlobalSettings")
        for setting in historicalUploadSettings {
            setting.reset()
        }
    }
    
    func resetCurrentUploadSettings() {
        DDLogVerbose("HKGlobalSettings")
        for setting in currentUploadSettings {
            setting.reset()
        }
    }
    
    init() {
        self.interfaceEnabled = HKSettingBool(key: "kHealthKitInterfaceEnabledKey")
        self.interfaceUserId = HKSettingString(key: "kUserIdForHealthKitInterfaceKey")
        self.interfaceUserName = HKSettingString(key: "kUserNameForHealthKitInterfaceKey")
        self.hkDataUploadId = HKSettingString(key: "kHKDataUploadIdKey")
        self.lastExecutedUploaderVersion = HKSettingInt(key: "LastExecutedUploaderVersionKey")
        self.hasPresentedSyncUI = HKSettingBool(key: "HasPresentedSyncUI")
        // global upload...
        self.historicalEndDate = HKSettingDate(key: "historicalEndDateKey")
        self.historicalLatestDate = HKSettingDate(key: "historicalLatestDateKey")
        self.historicalEarliestDate = HKSettingDate(key: "historicalEarliestDateKey")
        self.hasPendingHistoricalUploads = HKSettingBool(key: "hasPendingHistoricalUploadsKey")
        self.currentStartDate = HKSettingDate(key: "currentStartDateKey")
        self.hasPendingCurrentUploads = HKSettingBool(key: "hasPendingCurrentUploadsKey")
        self.lastSuccessfulCurrentUploadTime = HKSettingDate(key: "lastSuccessfulCurrentUploadTime")
        self.currentUploadEarliestSampleTime = HKSettingDate(key: "currentUploadEarliestSampleTime")
        self.currentUploadLatestSampleTime = HKSettingDate(key: "currentUploadLatestSampleTime")
        self.currentTotalSamplesUploadCount = HKSettingInt(key: "currentTotalSamplesUploadCount")
        self.currentTotalDeletesUploadCount = HKSettingInt(key: "currentTotalDeletesUploadCount")
        self.historicalTotalSamplesUploadCount = HKSettingInt(key: "historicalTotalSamplesUploadCount")
        self.historicalTotalDeletesUploadCount = HKSettingInt(key: "historicalTotalDeletesUploadCount")
        self.historicalUploadEarliestSampleTime = HKSettingDate(key: "historicalUploadEarliestSampleTime")
        self.historicalUploadLatestSampleTime = HKSettingDate(key: "historicalUploadLatestSampleTime")
        self.historicalTotalDays = HKSettingInt(key: "historicalTotalDays")
        self.historicalCurrentDay = HKSettingInt(key: "historicalCurrentDay")
        self.historicalIsResumable = HKSettingBool(key: "historicalIsResumable")

        // additional settings for global reset, used when switching HK user (all except lastExecutedUploaderVersion)
        self.userSettings = [
            self.interfaceEnabled,
            self.interfaceUserId,
            self.interfaceUserName,
            self.hkDataUploadId,
            self.hasPresentedSyncUI,
        ]
        self.historicalUploadSettings = [
            self.historicalEndDate,
            self.historicalEarliestDate,
            self.historicalLatestDate,
            self.hasPendingHistoricalUploads,
            self.historicalTotalSamplesUploadCount,
            self.historicalTotalDeletesUploadCount,
            self.historicalTotalDays,
            self.historicalCurrentDay,
            self.historicalUploadEarliestSampleTime,
            self.historicalUploadLatestSampleTime,
            self.historicalIsResumable
        ]
        self.currentUploadSettings = [
            self.currentStartDate,
            self.hasPendingCurrentUploads,
            self.lastSuccessfulCurrentUploadTime,
            self.currentUploadEarliestSampleTime,
            self.currentUploadLatestSampleTime,
            self.currentTotalSamplesUploadCount,
            self.currentTotalDeletesUploadCount
        ]

    }
    
    private var userSettings: [HKSettingType]
    private var historicalUploadSettings: [HKSettingType]
    private var currentUploadSettings: [HKSettingType]
}
