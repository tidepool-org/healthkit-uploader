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
        self.stats = TPUploaderStats()
        self.uploadType = type
        self.uploadTypeName = type.typeName
        self.mode = mode
        
        super.init()
        self.load()
    }

    private(set) var stats: TPUploaderStats
    
    fileprivate(set) var uploadType: HealthKitUploadType
    fileprivate(set) var uploadTypeName: String
    fileprivate(set) var mode: TPUploader.Mode

    func resetPersistentState() {
        DDLogVerbose("\(#function)")

        UserDefaults.standard.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsTotalUploadCountKey))

        UserDefaults.standard.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsStartDateHistoricalSamplesKey))
        UserDefaults.standard.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsEndDateHistoricalSamplesKey))
        UserDefaults.standard.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsTotalDaysHistoricalSamplesKey))
        UserDefaults.standard.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsCurrentDayHistoricalKey))
        
        UserDefaults.standard.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptTimeKey))
        UserDefaults.standard.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptSampleCountKey))
        UserDefaults.standard.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptEarliestSampleTimeKey))
        UserDefaults.standard.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptLatestSampleTimeKey))
        
        UserDefaults.standard.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastSuccessfulUploadTimeKey))
        UserDefaults.standard.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastSuccessfulUploadEarliestSampleTimeKey))
        UserDefaults.standard.removeObject(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastSuccessfulUploadLatestSampleTimeKey))
        
        UserDefaults.standard.synchronize()
        
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
        UserDefaults.standard.set(self.stats.lastUploadAttemptEarliestSampleTime, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptEarliestSampleTimeKey))

        self.stats.lastUploadAttemptLatestSampleTime = latestSampleTime
        UserDefaults.standard.set(self.stats.lastUploadAttemptLatestSampleTime, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptLatestSampleTimeKey))
        
        UserDefaults.standard.set(self.stats.lastUploadAttemptTime, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptTimeKey))
        UserDefaults.standard.set(self.stats.lastUploadAttemptSampleCount, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptSampleCountKey))
        
        UserDefaults.standard.synchronize()
        
        let uploadInfo : Dictionary<String, Any> = [
            "type" : self.uploadTypeName,
            "mode" : self.mode
        ]

        DispatchQueue.main.async {
            NotificationCenter.default.post(Notification(name: Notification.Name(rawValue: TPUploaderNotifications.Updated), object: self.mode, userInfo: uploadInfo))
        }
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
        UserDefaults.standard.set(self.stats.lastSuccessfulUploadEarliestSampleTime, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastSuccessfulUploadEarliestSampleTimeKey))

        self.stats.lastSuccessfulUploadLatestSampleTime = self.stats.lastUploadAttemptLatestSampleTime
        UserDefaults.standard.set(self.stats.lastSuccessfulUploadLatestSampleTime, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastSuccessfulUploadLatestSampleTimeKey))

        if self.mode != TPUploader.Mode.Current {
            if self.stats.totalDaysHistorical > 0 {
                self.stats.currentDayHistorical = self.stats.startDateHistoricalSamples.differenceInDays(self.stats.lastSuccessfulUploadLatestSampleTime)
            }
            UserDefaults.standard.set(self.stats.currentDayHistorical, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsCurrentDayHistoricalKey))
        }
        
        UserDefaults.standard.set(self.stats.lastSuccessfulUploadTime, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastSuccessfulUploadTimeKey))
        UserDefaults.standard.set(self.stats.totalUploadCount, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsTotalUploadCountKey))
        UserDefaults.standard.synchronize()
        
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
            
            if error != nil {
                DDLogError("Failed to update historical samples date range, error: \(String(describing: error))")
            } else if let startDate = startDate {
                self.stats.startDateHistoricalSamples = startDate
                
                let endDate = UserDefaults.standard.object(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.UploadQueryEndDateKey)) as? Date ?? Date()
                self.stats.endDateHistoricalSamples = endDate
                self.stats.totalDaysHistorical = self.stats.startDateHistoricalSamples.differenceInDays(self.stats.endDateHistoricalSamples) + 1
                
                UserDefaults.standard.set(self.stats.startDateHistoricalSamples, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsStartDateHistoricalSamplesKey))
                UserDefaults.standard.set(self.stats.endDateHistoricalSamples, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsEndDateHistoricalSamplesKey))
//                UserDefaults.standard.set(self.totalDaysHistorical, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsTotalDaysHistoricalSamplesKey))
                UserDefaults.standard.synchronize()
                
                DDLogInfo("Updated historical samples date range, start date:\(startDate), end date: \(endDate)")
            }
        }
    }

    func updateHistoricalSamplesDateRange(startDate: Date, endDate: Date) {
        self.stats.startDateHistoricalSamples = startDate
        self.stats.endDateHistoricalSamples = endDate
        self.stats.totalDaysHistorical = self.stats.startDateHistoricalSamples.differenceInDays(self.stats.endDateHistoricalSamples)
        
        UserDefaults.standard.set(self.stats.startDateHistoricalSamples, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsStartDateHistoricalSamplesKey))
        UserDefaults.standard.set(self.stats.endDateHistoricalSamples, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsEndDateHistoricalSamplesKey))
        UserDefaults.standard.set(self.stats.totalDaysHistorical, forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsTotalDaysHistoricalSamplesKey))
        UserDefaults.standard.synchronize()
    }
 
    // MARK: Private
    
    fileprivate func load(_ resetUser: Bool = false) {
        DDLogVerbose("\(#function)")
        
        let statsExist = UserDefaults.standard.object(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsTotalUploadCountKey)) != nil
        if statsExist {
            let lastSuccessfulUploadTime = UserDefaults.standard.object(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastSuccessfulUploadTimeKey)) as? Date
            self.stats.lastSuccessfulUploadTime = lastSuccessfulUploadTime ?? Date.distantPast

            let lastSuccessfulUploadLatestSampleTime = UserDefaults.standard.object(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastSuccessfulUploadLatestSampleTimeKey)) as? Date
            self.stats.lastSuccessfulUploadLatestSampleTime = lastSuccessfulUploadLatestSampleTime ?? Date.distantPast

            self.stats.totalUploadCount = UserDefaults.standard.integer(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsTotalUploadCountKey))
            
            let lastUploadAttemptTime = UserDefaults.standard.object(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptTimeKey)) as? Date
            self.stats.lastUploadAttemptTime = lastUploadAttemptTime ?? Date.distantPast
            
            let lastUploadAttemptEarliestSampleTime = UserDefaults.standard.object(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptEarliestSampleTimeKey)) as? Date
            self.stats.lastUploadAttemptEarliestSampleTime = lastUploadAttemptEarliestSampleTime ?? Date.distantPast

            let lastUploadAttemptLatestSampleTime = UserDefaults.standard.object(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptLatestSampleTimeKey)) as? Date
            self.stats.lastUploadAttemptLatestSampleTime = lastUploadAttemptLatestSampleTime ?? Date.distantPast

            self.stats.lastUploadAttemptSampleCount = UserDefaults.standard.integer(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsLastUploadAttemptSampleCountKey))
        } else {
            self.stats.lastSuccessfulUploadTime = Date.distantPast
            self.stats.lastSuccessfulUploadLatestSampleTime = Date.distantPast
            self.stats.totalUploadCount = 0

            self.stats.lastUploadAttemptTime = Date.distantPast
            self.stats.lastUploadAttemptEarliestSampleTime = Date.distantPast
            self.stats.lastUploadAttemptLatestSampleTime = Date.distantPast
            self.stats.lastUploadAttemptSampleCount = 0
        }

        if let startDateHistoricalSamplesObject = UserDefaults.standard.object(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsStartDateHistoricalSamplesKey)),
            let endDateHistoricalSamplesObject = UserDefaults.standard.object(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsEndDateHistoricalSamplesKey))
        {
            self.stats.totalDaysHistorical = UserDefaults.standard.integer(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsTotalDaysHistoricalSamplesKey))
            self.stats.currentDayHistorical = UserDefaults.standard.integer(forKey: HealthKitSettings.prefixedKey(prefix: self.mode.rawValue, type: self.uploadTypeName, key: HealthKitSettings.StatsCurrentDayHistoricalKey))
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
