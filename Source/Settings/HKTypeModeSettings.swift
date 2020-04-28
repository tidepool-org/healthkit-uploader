//
//  HKTypeModeSettings.swift
//  TPHealthKitUploader
//
//  Created by Larry Kenyon on 4/8/19.
//  Copyright © 2019 Tidepool. All rights reserved.
//

import Foundation

class HKTypeModeSettings {

    private(set) var typeName: String
    private(set) var mode: TPUploader.Mode

    // Attempt stats .. not persisted .. used privately
    var lastUploadSamplesAttemptEarliestSampleTime: Date? = nil
    var lastUploadSamplesAttemptLatestSampleTime: Date? = nil
    var lastUploadSamplesAttemptCount = 0
    var lastUploadDeletesAttemptCount = 0
  
    // Batch stats .. not persisted .. used privately
    var lastSuccessfulUploadEarliestSampleTimeInBatch: Date? = nil
    var lastSuccessfulUploadLatestSampleTimeInBatch: Date? = nil
    var historicalTotalDaysInBatch = 0
    var historicalCurrentDayInBatch = 0
    var totalSamplesUploadCountInBatch = 0
    var totalDeletesUploadCountInBatch = 0

    // Persistent settings
    var totalSamplesCount: HKSettingInt
    var totalSamplesUploadCount: HKSettingInt
    var totalDeletesUploadCount: HKSettingInt
    var lastSuccessfulUploadLatestSampleTime: HKSettingDate
    var lastSuccessfulUploadEarliestSampleTime: HKSettingDate
    var startDateHistoricalSamples: HKSettingDate
    var endDateHistoricalSamples: HKSettingDate
    var lastSuccessfulUploadTime: HKSettingDate
    var historicalTotalDaysCount: HKSettingInt
    var historicalCurrentDay: HKSettingInt
    var historicalTotalSamplesCount: HKSettingInt
  
    // Reader settings
    var queryAnchor: HKSettingAnchor

    func stats() -> TPUploaderStats {
        DDLogVerbose("HKTypeModeSettings (\(typeName), \(mode))")
        var result = TPUploaderStats(typeName: typeName, mode: mode)
        result.hasSuccessfullyUploaded = self.totalSamplesUploadCount.value > 0
        result.lastSuccessfulUploadTime = self.lastSuccessfulUploadTime.value
        result.totalDaysHistorical = historicalTotalDaysCount.value
        result.currentDayHistorical = historicalCurrentDay.value
        result.totalSamplesHistorical = historicalTotalSamplesCount.value
        result.lastSuccessfulUploadEarliestSampleTime = self.lastSuccessfulUploadEarliestSampleTime.value
        result.lastSuccessfulUploadLatestSampleTime = self.lastSuccessfulUploadLatestSampleTime.value
        result.startDateHistoricalSamples = self.startDateHistoricalSamples.value
        result.endDateHistoricalSamples = self.endDateHistoricalSamples.value
        result.totalSamplesUploadCount = self.totalSamplesUploadCount.value
        result.totalDeletesUploadCount = self.totalDeletesUploadCount.value
        result.totalSamplesCount = self.totalSamplesCount.value
        return result
    }
    
    func resetAllStatsKeys() {
        DDLogVerbose("HKTypeModeSettings (\(typeName), \(mode))")
        for setting in statSettings {
            setting.reset()
        }
        // also reset all the non-persisted info
        resetSamplesBatchStats()
        resetDeletesBatchStats()
        resetSamplesAttemptStats()
        resetDeletesAttemptStats()
    }
    
    func resetAllReaderKeys() {
        DDLogVerbose("HKTypeModeSettings (\(typeName), \(mode))")
        for setting in readerSettings {
            setting.reset()
        }
    }

    func resetSamplesBatchStats() {
        lastSuccessfulUploadEarliestSampleTimeInBatch = nil
        lastSuccessfulUploadLatestSampleTimeInBatch = nil
        historicalTotalDaysInBatch = 0
        historicalCurrentDayInBatch = 0
        totalSamplesUploadCountInBatch = 0
    }
  
    func resetDeletesBatchStats() {
        totalDeletesUploadCountInBatch = 0
    }

    func resetSamplesAttemptStats() {
        DDLogVerbose("HKTypeModeSettings: (\(typeName), \(mode.rawValue))")
        lastUploadSamplesAttemptEarliestSampleTime = nil
        lastUploadSamplesAttemptLatestSampleTime = nil
        lastUploadSamplesAttemptCount = 0
    }

    func resetDeletesAttemptStats() {
        DDLogVerbose("HKTypeModeSettings: (\(typeName), \(mode.rawValue))")
        lastUploadDeletesAttemptCount = 0
    }
    
    func updateForHistoricalSampleDateRange(startDate: Date, endDate: Date) {
        self.startDateHistoricalSamples.value = startDate
        self.endDateHistoricalSamples.value = endDate
        if self.startDateHistoricalSamples.value != Date.distantFuture {
            self.historicalTotalDaysCount.value = self.startDateHistoricalSamples.value!.differenceInDays(self.endDateHistoricalSamples.value!) + 1
        } else {
            self.historicalTotalDaysCount.value = 0
        }
      
        DDLogInfo("Updated historical samples date range for \(typeName): start date \(startDate), end date \(endDate), total days: \(self.historicalTotalDaysCount.value)")
    }
  
    func updateForHistoricalSampleCount(_ count: Int) {
        self.historicalTotalSamplesCount.value += count
        DDLogInfo("Updated historical sample count for \(typeName): total samples: \(count)")
    }

    func updateForSamplesUploadAttempt(sampleCount: Int, uploadAttemptTime: Date, earliestSampleTime: Date, latestSampleTime: Date) {
        DDLogInfo("(\(self.mode),  \(self.typeName)) Prepared samples for upload: \(sampleCount) samples, at: \(uploadAttemptTime), with earliest sample time: \(earliestSampleTime), with latest sample time: \(latestSampleTime)")
        
        self.lastUploadSamplesAttemptCount += sampleCount
        guard sampleCount > 0 else {
            DDLogInfo("Upload with zero samples (deletes only)")
            return
        }
        self.lastUploadSamplesAttemptEarliestSampleTime = earliestSampleTime
        self.lastUploadSamplesAttemptLatestSampleTime = latestSampleTime
    }

    func updateForDeletesUploadAttempt(deleteCount: Int, uploadAttemptTime: Date) {
        DDLogInfo("(\(self.mode),  \(self.typeName)) Prepared deletes for upload: \(deleteCount) at: \(uploadAttemptTime)")
        
        self.lastUploadDeletesAttemptCount += deleteCount
    }
  
    func updateForSuccessfulSamplesUploadInBatch() {
        if self.lastUploadSamplesAttemptCount > 0 {
            self.totalSamplesUploadCountInBatch += self.lastUploadSamplesAttemptCount
            
            if let lastUploadSamplesAttemptEarliestSampleTime = self.lastUploadSamplesAttemptEarliestSampleTime {
                if self.lastSuccessfulUploadEarliestSampleTimeInBatch == nil || lastUploadSamplesAttemptEarliestSampleTime < self.lastSuccessfulUploadEarliestSampleTimeInBatch! {
                    self.lastSuccessfulUploadEarliestSampleTimeInBatch = lastUploadSamplesAttemptEarliestSampleTime
                }
            }
            if let lastUploadSamplesAttemptLatestSampleTime = self.lastUploadSamplesAttemptLatestSampleTime {
                if self.lastSuccessfulUploadLatestSampleTimeInBatch == nil || lastUploadSamplesAttemptLatestSampleTime > self.lastSuccessfulUploadLatestSampleTimeInBatch! {
                    self.lastSuccessfulUploadLatestSampleTimeInBatch = lastUploadSamplesAttemptLatestSampleTime
                }
            }
          
            if mode == .HistoricalAll {
                if let earliestDay = self.startDateHistoricalSamples.value, let latestDay = self.endDateHistoricalSamples.value {
                    if earliestDay.compare(latestDay) != .orderedSame {
                        self.historicalTotalDaysInBatch = earliestDay.differenceInDays(latestDay) + 1
                        if let currentDay = lastSuccessfulUploadLatestSampleTimeInBatch {
                          self.historicalCurrentDayInBatch = earliestDay.differenceInDays(currentDay) + 1
                        }
                    }
                }
            }
        }
    }

    func updateForSuccessfulDeletesUploadInBatch() {
        if self.lastUploadDeletesAttemptCount > 0 {
            self.totalDeletesUploadCountInBatch += self.lastUploadDeletesAttemptCount
        }
    }

    func updateForFinalSuccessfulUploadInBatch(lastSuccessfulUploadTime: Date) {
        DDLogVerbose("HKTypeModeSettings: (\(self.mode),  \(self.typeName))")
        
        if self.totalSamplesUploadCountInBatch > 0 {
            self.totalSamplesUploadCount.value += self.totalSamplesUploadCountInBatch
            self.lastSuccessfulUploadTime.value = lastSuccessfulUploadTime
          
            if let lastSuccessfulUploadEarliestSampleTimeInBatch = self.lastSuccessfulUploadEarliestSampleTimeInBatch {
                if self.lastSuccessfulUploadEarliestSampleTime.value == nil || lastSuccessfulUploadEarliestSampleTimeInBatch < self.lastSuccessfulUploadEarliestSampleTime.value! {
                    self.lastSuccessfulUploadEarliestSampleTime.value = lastSuccessfulUploadEarliestSampleTimeInBatch
                }
            }
            if let lastSuccessfulUploadLatestSampleTimeInBatch = self.lastSuccessfulUploadLatestSampleTimeInBatch {
                if self.lastSuccessfulUploadLatestSampleTime.value == nil || lastSuccessfulUploadLatestSampleTimeInBatch > self.lastSuccessfulUploadLatestSampleTime.value! {
                    self.lastSuccessfulUploadLatestSampleTime.value = lastSuccessfulUploadLatestSampleTimeInBatch
                }
            }
          
            if mode == .HistoricalAll {
                self.historicalCurrentDay.value = self.historicalCurrentDayInBatch
            }
                
            let message = "(\(self.mode),  \(self.typeName)) Successfully uploaded \(self.totalSamplesUploadCountInBatch) samples, upload time: \(String(describing: lastSuccessfulUploadTime)), earliest sample time: \(String(describing: self.lastSuccessfulUploadEarliestSampleTime.value)), latest sample time: \(String(describing: self.lastSuccessfulUploadLatestSampleTime.value))"
            DDLogInfo(message)
        }
      
        if self.totalDeletesUploadCountInBatch > 0 {
            self.totalDeletesUploadCount.value += self.totalDeletesUploadCountInBatch
            let message = "(\(self.mode),  \(self.typeName)) Successfully uploaded \(self.totalDeletesUploadCountInBatch) deletes, upload time: \(String(describing: lastSuccessfulUploadTime))"
            DDLogInfo(message)
        }

        if self.totalSamplesUploadCountInBatch > 0 || self.totalDeletesUploadCountInBatch > 0 {
            postNotifications([TPUploaderNotifications.Updated, TPUploaderNotifications.UploadSuccessful])
        }
    }

    //
    // MARK: - Private
    //
    
    let defaults = UserDefaults.standard
    
    internal var statSettings: [HKSettingType]
    internal var readerSettings: [HKSettingType]

    init(mode: TPUploader.Mode, typeName: String) {
        DDLogVerbose("HKTypeModeSettings (\(typeName), \(mode))")
        self.typeName = typeName
        self.mode = mode
        
        func prefixedKey(_ key: String) -> String {
            let result = "\(mode.rawValue)-\(typeName)\(key)"
            return result
        }
        
        self.totalSamplesUploadCount = HKSettingInt(key: prefixedKey("StatsTotalSamplesUploadCount"))
        self.totalDeletesUploadCount = HKSettingInt(key: prefixedKey("StatsTotalDeletesUploadCount"))
        self.totalSamplesCount = HKSettingInt(key: prefixedKey("totalSamplesCount"))
        self.lastSuccessfulUploadTime = HKSettingDate(key: prefixedKey("StatsLastSuccessfulUploadTimeKey"))
        self.lastSuccessfulUploadLatestSampleTime = HKSettingDate(key: prefixedKey("StatsLastSuccessfulUploadLatestSampleTimeKey"))
        self.lastSuccessfulUploadEarliestSampleTime = HKSettingDate(key: prefixedKey("StatsLastSuccessfulUploadEarliestSampleTimeKey"))
        self.startDateHistoricalSamples = HKSettingDate(key: prefixedKey("StatsStartDateHistoricalSamplesKey"))
        self.endDateHistoricalSamples = HKSettingDate(key: prefixedKey("StatsEndDateHistoricalSamplesKey"))
        self.historicalTotalDaysCount = HKSettingInt(key: prefixedKey("StatsHistoricalTotalDays"))
        self.historicalCurrentDay = HKSettingInt(key: prefixedKey("StatsHistoricalCurrentDay"))
        self.historicalTotalSamplesCount = HKSettingInt(key: prefixedKey("StatsHistoricalTotalSamples"))
        self.queryAnchor = HKSettingAnchor(key: prefixedKey("QueryAnchorKey"))

        statSettings = [
            self.totalSamplesUploadCount,
            self.totalDeletesUploadCount,
            self.totalSamplesCount,
            self.startDateHistoricalSamples,
            self.endDateHistoricalSamples,
            self.lastSuccessfulUploadTime,
            self.lastSuccessfulUploadLatestSampleTime,
            self.lastSuccessfulUploadEarliestSampleTime,
            self.historicalTotalDaysCount,
            self.historicalCurrentDay,
            self.historicalTotalSamplesCount
        ]
        
        readerSettings = [
            self.queryAnchor]
    }

    private func postNotifications(_ notificationNames: [String]) {
        let uploadInfo : Dictionary<String, Any> = [
            "type" : self.typeName,
            "mode" : self.mode
        ]
        DispatchQueue.main.async {
            for name in notificationNames {
                NotificationCenter.default.post(Notification(name: Notification.Name(rawValue: name), object: self.mode, userInfo: uploadInfo))
            }
        }
    }

}
