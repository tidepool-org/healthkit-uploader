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

class HealthKitUploadStats: NSObject {
    
    init(type: HealthKitUploadType, mode: TPUploader.Mode) {
        DDLogVerbose("\(#function)")
        self.stats = TPUploaderStats(typeName: type.typeName, mode: mode)
        self.uploadType = type
        self.uploadTypeName = type.typeName
        self.mode = mode
        
        super.init()
        self.load()
    }

    private let defaults = UserDefaults.standard
    private(set) var stats: TPUploaderStats
    
    private(set) var uploadType: HealthKitUploadType
    private(set) var uploadTypeName: String
    private(set) var mode: TPUploader.Mode

    private enum statKey {
        case uploadCount
        case startDateHistorical
        case endDataHistorical
    }
    
    private let allStatKeys: [statKey] = [.uploadCount, .startDateHistorical, .endDataHistorical]
    private let statKeyDict: [statKey: String] = [
        .uploadCount: HealthKitSettings.StatsTotalUploadCountKey,
        .startDateHistorical: HealthKitSettings.StatsStartDateHistoricalSamplesKey,
        .endDataHistorical: HealthKitSettings.StatsEndDateHistoricalSamplesKey
    ]
    
    private func removeStatForKey(_ key: statKey) {
        if let keyName = statKeyDict[key] {
            defaults.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: keyName))
        } else {
            DDLogError("MISSING KEY!")
        }
    }
    
    func resetPersistentState() {
        DDLogVerbose("HealthKitUploadStats:\(#function) type: \(uploadType.typeName), mode: \(mode.rawValue)")

        for key in allStatKeys {
            removeStatForKey(key)
        }
        
        defaults.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsTotalUploadCountKey))

        defaults.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsStartDateHistoricalSamplesKey))
        defaults.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsEndDateHistoricalSamplesKey))
        defaults.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsTotalDaysHistoricalSamplesKey))
        defaults.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsCurrentDayHistoricalKey))
        
        defaults.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptTimeKey))
        defaults.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptSampleCountKey))
        defaults.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptEarliestSampleTimeKey))
        defaults.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptLatestSampleTimeKey))
        
        defaults.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastSuccessfulUploadTimeKey))
        defaults.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastSuccessfulUploadEarliestSampleTimeKey))
        defaults.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastSuccessfulUploadLatestSampleTimeKey))
        
        self.load()
    }

    func updateForUploadAttempt(sampleCount: Int, uploadAttemptTime: Date, earliestSampleTime: Date, latestSampleTime: Date) {
        DDLogInfo("Attempting to upload: \(sampleCount) samples, at: \(uploadAttemptTime), with earliest sample time: \(earliestSampleTime), with latest sample time: \(latestSampleTime), mode: \(self.mode), type: \(self.uploadTypeName)")
        
        self.stats.lastUploadAttemptTime = uploadAttemptTime
        self.stats.lastUploadAttemptSampleCount = sampleCount
        
        guard sampleCount > 0 else {
            DDLogInfo("Upload with zero samples (deletes only)")
            return
        }
        
        self.stats.lastUploadAttemptEarliestSampleTime = earliestSampleTime
        defaults.set(self.stats.lastUploadAttemptEarliestSampleTime, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptEarliestSampleTimeKey))

        self.stats.lastUploadAttemptLatestSampleTime = latestSampleTime
        defaults.set(self.stats.lastUploadAttemptLatestSampleTime, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptLatestSampleTimeKey))
        
        defaults.set(self.stats.lastUploadAttemptTime, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptTimeKey))
        defaults.set(self.stats.lastUploadAttemptSampleCount, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptSampleCountKey))
        
        let uploadInfo : Dictionary<String, Any> = [
            "type" : self.uploadTypeName,
            "mode" : self.mode
        ]

        DispatchQueue.main.async {
            NotificationCenter.default.post(Notification(name: Notification.Name(rawValue: TPUploaderNotifications.Updated), object: self.mode, userInfo: uploadInfo))
        }
    }
    
    func updateHistoricalStatsForEndState() {
        // call when upload finishes because no more data has been found. This simply moves the curret day pointer to the end...
        self.stats.currentDayHistorical = self.stats.totalDaysHistorical
        defaults.set(self.stats.currentDayHistorical, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsCurrentDayHistoricalKey))
    }
    
    func updateForSuccessfulUpload(lastSuccessfulUploadTime: Date) {
        DDLogVerbose("\(#function)")
        
        guard self.stats.lastUploadAttemptSampleCount > 0 else {
            DDLogInfo("Skip update for delete only uploads, date range unknown")
            return
        }
        
        self.stats.totalUploadCount += self.stats.lastUploadAttemptSampleCount
        self.stats.hasSuccessfullyUploaded = self.stats.totalUploadCount > 0
        self.stats.lastSuccessfulUploadTime = lastSuccessfulUploadTime

        self.stats.lastSuccessfulUploadEarliestSampleTime = self.stats.lastUploadAttemptEarliestSampleTime
        defaults.set(self.stats.lastSuccessfulUploadEarliestSampleTime, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastSuccessfulUploadEarliestSampleTimeKey))

        self.stats.lastSuccessfulUploadLatestSampleTime = self.stats.lastUploadAttemptLatestSampleTime
        defaults.set(self.stats.lastSuccessfulUploadLatestSampleTime, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastSuccessfulUploadLatestSampleTimeKey))

        if self.mode != TPUploader.Mode.Current {
            if self.stats.totalDaysHistorical > 0 {
                self.stats.currentDayHistorical = self.stats.startDateHistoricalSamples.differenceInDays(self.stats.lastSuccessfulUploadLatestSampleTime)
            }
            defaults.set(self.stats.currentDayHistorical, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsCurrentDayHistoricalKey))
        }
        
        defaults.set(self.stats.lastSuccessfulUploadTime, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastSuccessfulUploadTimeKey))
        defaults.set(self.stats.totalUploadCount, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsTotalUploadCountKey))
        
        let message = "Successfully uploaded \(self.stats.lastUploadAttemptSampleCount) samples, upload time: \(lastSuccessfulUploadTime), earliest sample date: \(self.stats.lastSuccessfulUploadEarliestSampleTime), latest sample date: \(self.stats.lastSuccessfulUploadLatestSampleTime), mode: \(self.mode), type: \(self.uploadTypeName). "
        DDLogInfo(message)
        if self.stats.totalDaysHistorical > 0 {
            DDLogInfo("Uploaded \(self.stats.currentDayHistorical) of \(self.stats.totalDaysHistorical) days of historical data")
        }

        let uploadInfo : Dictionary<String, Any> = [
            "type" : self.uploadTypeName,
            "mode" : self.mode
        ]

        DispatchQueue.main.async {
            NotificationCenter.default.post(Notification(name: Notification.Name(rawValue: TPUploaderNotifications.Updated), object: self.mode, userInfo: uploadInfo))
            NotificationCenter.default.post(Notification(name: Notification.Name(rawValue: TPUploaderNotifications.UploadSuccessful), object: self.mode, userInfo: uploadInfo))
        }
    }

    func updateHistoricalSamplesDateRangeFromHealthKitAsync() {
        DDLogVerbose("\(#function)")
        
        let sampleType = uploadType.hkSampleType()!
        HealthKitManager.sharedInstance.findSampleDateRange(sampleType: sampleType) {
            (error: NSError?, startDate: Date?, endDate: Date?) in
            let defaults = UserDefaults.standard
            
            if error != nil {
                DDLogError("Failed to update historical samples date range, error: \(String(describing: error))")
            } else if let startDate = startDate {
                self.stats.startDateHistoricalSamples = startDate
                
                let endDate = defaults.object(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.UploadQueryEndDateKey)) as? Date ?? Date()
                self.stats.endDateHistoricalSamples = endDate
                self.stats.totalDaysHistorical = self.stats.startDateHistoricalSamples.differenceInDays(self.stats.endDateHistoricalSamples) + 1
                
                defaults.set(self.stats.startDateHistoricalSamples, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsStartDateHistoricalSamplesKey))
                defaults.set(self.stats.endDateHistoricalSamples, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsEndDateHistoricalSamplesKey))
                defaults.set(self.stats.totalDaysHistorical, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsTotalDaysHistoricalSamplesKey))
                
                DDLogInfo("Updated historical samples date range, start date:\(startDate), end date: \(endDate)")
            }
        }
    }
 
    // MARK: Private
    
    fileprivate func load(_ resetUser: Bool = false) {
        DDLogVerbose("\(#function)")
        
        let statsExist = defaults.object(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsTotalUploadCountKey)) != nil
        if statsExist {
            let lastSuccessfulUploadTime = defaults.object(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastSuccessfulUploadTimeKey)) as? Date
            self.stats.lastSuccessfulUploadTime = lastSuccessfulUploadTime ?? Date.distantPast

            let lastSuccessfulUploadLatestSampleTime = defaults.object(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastSuccessfulUploadLatestSampleTimeKey)) as? Date
            self.stats.lastSuccessfulUploadLatestSampleTime = lastSuccessfulUploadLatestSampleTime ?? Date.distantPast

            self.stats.totalUploadCount = defaults.integer(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsTotalUploadCountKey))
            
            let lastUploadAttemptTime = defaults.object(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptTimeKey)) as? Date
            self.stats.lastUploadAttemptTime = lastUploadAttemptTime ?? Date.distantPast
            
            let lastUploadAttemptEarliestSampleTime = defaults.object(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptEarliestSampleTimeKey)) as? Date
            self.stats.lastUploadAttemptEarliestSampleTime = lastUploadAttemptEarliestSampleTime ?? Date.distantPast

            let lastUploadAttemptLatestSampleTime = defaults.object(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptLatestSampleTimeKey)) as? Date
            self.stats.lastUploadAttemptLatestSampleTime = lastUploadAttemptLatestSampleTime ?? Date.distantPast

            self.stats.lastUploadAttemptSampleCount = defaults.integer(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptSampleCountKey))
        } else {
            self.stats.lastSuccessfulUploadTime = Date.distantPast
            self.stats.lastSuccessfulUploadLatestSampleTime = Date.distantPast
            self.stats.totalUploadCount = 0

            self.stats.lastUploadAttemptTime = Date.distantPast
            self.stats.lastUploadAttemptEarliestSampleTime = Date.distantPast
            self.stats.lastUploadAttemptLatestSampleTime = Date.distantPast
            self.stats.lastUploadAttemptSampleCount = 0
        }

        if let startDateHistoricalSamplesObject = defaults.object(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsStartDateHistoricalSamplesKey)),
            let endDateHistoricalSamplesObject = defaults.object(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsEndDateHistoricalSamplesKey))
        {
            self.stats.totalDaysHistorical = defaults.integer(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsTotalDaysHistoricalSamplesKey))
            self.stats.currentDayHistorical = defaults.integer(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsCurrentDayHistoricalKey))
            self.stats.startDateHistoricalSamples = startDateHistoricalSamplesObject as? Date ?? Date.distantPast
            self.stats.endDateHistoricalSamples = endDateHistoricalSamplesObject as? Date ?? Date.distantPast
        } else {
            self.stats.totalDaysHistorical = 0
            self.stats.currentDayHistorical = 0
            self.stats.startDateHistoricalSamples = Date.distantPast
            self.stats.endDateHistoricalSamples = Date.distantPast
        }

        self.stats.hasSuccessfullyUploaded = self.stats.totalUploadCount > 0
    }
}
