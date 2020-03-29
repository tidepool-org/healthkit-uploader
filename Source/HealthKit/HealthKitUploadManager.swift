/*
* Copyright (c) 2016-2018, Tidepool Project
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

// Note: The current phase start date is set some time delta in the past. Set it to 4 hours to pick up deletes from Loop that occur 3 hours after Dexcom samples are reported, since only the current upload picks up new deletes (anchor query).
let kCurrentStartTimeInPast: TimeInterval = (-60 * 60 * 4)

class HealthKitUploadManager:
        NSObject,
        URLSessionDelegate,
        URLSessionTaskDelegate
{
    static let sharedInstance = HealthKitUploadManager()
    let settings = HKGlobalSettings.sharedInstance

    private override init() {
        DDLogVerbose("\(#function)")

        currentHelper = HealthKitUploadHelper(.Current)
        historicalHelper = HealthKitUploadHelper(.HistoricalAll)
        super.init()

        // Reset persistent uploader state if uploader version is upgraded in a way that breaks persistent state, or if we have a reason to force all users to reupload
        let latestUploaderVersion = 10
        let lastExecutedUploaderVersion = settings.lastExecutedUploaderVersion.value
        DDLogVerbose("Uploader version: (latestUploaderVersion)")
        if latestUploaderVersion != lastExecutedUploaderVersion {
            DDLogInfo("Migrating uploader from: \(lastExecutedUploaderVersion) to: \(latestUploaderVersion)")
            settings.lastExecutedUploaderVersion.value = latestUploaderVersion
            self.resetPersistentState(switchingHealthKitUsers: false)
        }
    }
    private var currentHelper: HealthKitUploadHelper
    private var historicalHelper: HealthKitUploadHelper
    private var config: TPUploaderConfigInfo? // Set during upload (start or resume)

    /// Return array of stats per type for specified mode
    func statsForMode(_ mode: TPUploader.Mode) -> [TPUploaderStats] {
        let helper = mode == .Current ? currentHelper : historicalHelper
        var result: [TPUploaderStats] = []
        for reader in helper.readers {
            result.append(reader.readerSettings.stats())
        }
        return result
    }

    func isUploadInProgressForMode(_ mode: TPUploader.Mode) -> Bool {
        let helper = mode == .Current ? currentHelper : historicalHelper
        let isUploading = helper.isUploading
        DDLogVerbose("returning \(isUploading) for mode \(mode)")
        return isUploading
    }

    func retryInfoForMode(_ mode: TPUploader.Mode) -> (Int, Int) {
      let helper = mode == .Current ? currentHelper : historicalHelper
      let limitsIndex = helper.uploadLimitsIndex
      let maxLimitsIndex = helper.samplesUploadLimits.count - 1
      return (limitsIndex, maxLimitsIndex)
    }

    func resetPersistentStateForMode(_ mode: TPUploader.Mode) {
        DDLogVerbose("\(mode)")
        let helper = mode == .Current ? currentHelper : historicalHelper
        helper.resetPersistentState()
        if mode == .HistoricalAll {
            settings.resetHistoricalUploadSettings()
        } else {
            // mode == .Current
            settings.resetCurrentUploadSettings()
        }
    }

    func resetPersistentState(switchingHealthKitUsers: Bool) {
        DDLogVerbose("switchingHealthKitUsers: \(switchingHealthKitUsers)")
        currentHelper.resetPersistentState()
        historicalHelper.resetPersistentState()
        if switchingHealthKitUsers {
            settings.resetAll()
        }
    }

    func startUploading(mode: TPUploader.Mode, config: TPUploaderConfigInfo) {
        DDLogVerbose("mode: \(mode.rawValue)")

        self.config = config
        let helper = mode == .Current ? currentHelper : historicalHelper

        // Start at index 1 instead of 0 so first so we can show status more quickly to the user, and so that background mode is more likely to finish quickly?
        helper.startUploading(config: config, currentUserId: config.currentUserId()!, samplesUploadLimits: config.samplesUploadLimits(), deletesUploadLimits: config.deletesUploadLimits(), uploaderTimeouts: config.uploaderTimeouts(), uploadLimitsIndex: 1)
     }

    func stopUploading(mode: TPUploader.Mode, reason: TPUploader.StoppedReason) {
        DDLogVerbose("(\(mode.rawValue)) reason: \(reason)")
        let helper = mode == .Current ? currentHelper : historicalHelper
        helper.stopUploading(reason: reason)
    }

    func stopUploading(reason: TPUploader.StoppedReason) {
        DDLogVerbose("reason: \(reason)")
        self.stopUploading(mode: .Current, reason: reason)
        self.stopUploading(mode: .HistoricalAll, reason: reason)
    }

    func resumeUploadingIfResumable(config: TPUploaderConfigInfo) {
        DDLogVerbose("")
        self.config = config
        if TPUploaderServiceAPI.connector?.currentUploadId != nil {
          currentHelper.resumeUploadingIfResumable(config: config, currentUserId: config.currentUserId(), samplesUploadLimits: config.samplesUploadLimits(), deletesUploadLimits: config.deletesUploadLimits(), uploaderTimeouts: config.uploaderTimeouts())
          historicalHelper.resumeUploadingIfResumable(config: config, currentUserId: config.currentUserId(), samplesUploadLimits: config.samplesUploadLimits(), deletesUploadLimits: config.deletesUploadLimits(), uploaderTimeouts: config.uploaderTimeouts())
        } else {
            DDLogError("Unable to resumeUploading - no currentUploadId available!")
        }
    }
}

//
// MARK: - Private helper class
//

import UIKit  // for UIApplication...

/// Helper class to apply functions to each type of upload data
private class HealthKitUploadHelper: HealthKitSampleUploaderDelegate, HealthKitUploadReaderDelegate {

    init(_ mode: TPUploader.Mode) {
        self.mode = mode
        self.uploader = HealthKitUploader(mode)
        self.uploader.delegate = self
        // init reader, stats for the different types
        let hkTypes = HealthKitConfiguration.sharedInstance.healthKitUploadTypes
        for hkType in hkTypes {
            let reader = HealthKitUploadReader(type: hkType, mode: self.mode)
            reader.delegate = self
            self.readers.append(reader)
        }
    }

    private let mode: TPUploader.Mode
    private var requestTimeoutInterval: TimeInterval = 60
    private(set) var readers: [HealthKitUploadReader] = []
    private var uploader: HealthKitUploader
    private(set) var isUploading: Bool = false
    private(set) var isRetry: Bool = false
    private var startTime: Date = Date()
    private(set) var uploadLimitsIndex: Int = 0
    private var didResetUploadAttemptsRemaining: Bool = false
    private var uploadAttemptsRemaining: Int = 1 // Number of upload attempts remaining at current index
    private(set) var samplesUploadLimits: [Int] = [500]
    private(set) var deletesUploadLimits: [Int] = [500]
    private(set) var uploaderTimeouts: [Int] = [60]
    private var samplesToUpload = [[String: AnyObject]]()
    private var config: TPUploaderConfigInfo? // Set during upload (start or resume)
    // dates of first and last samples in samplesToUpload buffer
    private var firstSampleDate: Date?
    private var lastSampleDate: Date?
    private var deletesToUpload = [[String: AnyObject]]()
    let settings = HKGlobalSettings.sharedInstance

    func resetPersistentState() {
        DDLogVerbose("helper resetPersistentState (\(mode.rawValue))")
        for reader in readers {
            reader.resetPersistentStateOfReader()
        }
        resetForNextBatch()
    }

    private func resetForNextBatch() {
        for reader in self.readers {
            reader.resetReadBuffers()
            reader.resetSamplesUploadStats()
            reader.resetDeletesUploadStats()
            reader.reloadQueryAnchor()
        }
        self.resetSamplesUploadBuffers()
        self.resetDeletesUploadBuffers()
    }
  
    private func resetSamplesUploadBuffers() {
        self.samplesToUpload = []
        self.firstSampleDate = nil
        self.lastSampleDate = nil
    }

    private func resetDeletesUploadBuffers() {
        self.deletesToUpload = []
    }

    private func gatherUploadSamples() {
        self.resetSamplesUploadBuffers()
      
      // get readers that still have samples...
        var readersWithSamples: [HealthKitUploadReader] = []
        for reader in readers {
            reader.resetSamplesAttemptStats()
            if reader.nextSampleDate() != nil {
                readersWithSamples.append(reader)
            }
        }
        DDLogVerbose("readersWithSamples: \(readersWithSamples.count)")
        guard readersWithSamples.count > 0 else {
            return
        }
        // loop to get next group of samples to upload
        var nextReader: HealthKitUploadReader?
        repeat {
            nextReader = nil
            var nextSampleDate: Date?
            for reader in readersWithSamples {
                if let sampleDate = reader.nextSampleDate() {
                    if nextSampleDate == nil {
                        nextSampleDate = sampleDate
                        nextReader = reader
                    } else {
                        if sampleDate.compare(nextSampleDate!) == .orderedDescending {
                            nextSampleDate = sampleDate
                            nextReader = reader
                        }
                    }
                }
            }
            if let reader = nextReader {
                if let nextSample = reader.popNextSample() {
                    if let sampleAsDict = reader.sampleToUploadDict(nextSample) {
                        samplesToUpload.append(sampleAsDict)
                        // remember first and last sample dates for stats...
                        if self.lastSampleDate == nil {
                            self.lastSampleDate = nextSampleDate
                        }
                        self.firstSampleDate = nextSampleDate
                    }
                }
            }
        } while nextReader != nil && samplesToUpload.count < samplesUploadLimits[uploadLimitsIndex]
        // let each reader note attempt progress...
        let uploadTime = Date()
        for reader in readersWithSamples {
            reader.reportNextUploadSamplesStatsAtTime(uploadTime)
        }
        DDLogInfo("found samples to upload: \(samplesToUpload.count) at: \(uploadTime)")
        // note upload attempt...
        if let firstSampleDate = self.firstSampleDate, let lastSampleDate = self.lastSampleDate {
            DDLogVerbose("sample date range earliest: \(firstSampleDate), latest: \(lastSampleDate) (\(self.mode))")
        }
    }

    // Deletes are not dated, so can't be uploaded in any order. Just load up to n deletes...
    private func gatherUploadDeletes() {
        self.resetDeletesUploadBuffers()
      
        // loop through all readers to get any deletes...
        for reader in readers {
            reader.resetDeletesAttemptStats()
            var nextDeleteDict: [String: AnyObject]?
            repeat {
                nextDeleteDict = reader.nextDeletedSampleDict()
                if nextDeleteDict != nil {
                    deletesToUpload.append(nextDeleteDict!)
                }
            } while nextDeleteDict != nil && deletesToUpload.count < deletesUploadLimits[uploadLimitsIndex]
            if deletesToUpload.count >= deletesUploadLimits[uploadLimitsIndex] {
                break
            }
        }
        // let each reader note attempt progress...
        let uploadTime = Date()
        for reader in readers {
            reader.reportNextUploadDeletesStatsAtTime(uploadTime)
        }
        DDLogInfo("found delete samples to upload: \(deletesToUpload.count) at: \(uploadTime)")
    }

    func startUploading(config: TPUploaderConfigInfo, currentUserId: String, samplesUploadLimits: [Int], deletesUploadLimits: [Int], uploaderTimeouts: [Int], uploadLimitsIndex: Int = 0, uploadAttemptsRemaining: Int = 1, isRetry: Bool = false) {
        DDLogVerbose("(\(mode.rawValue))")

        let wasUploading = self.isUploading
        guard !wasUploading || isRetry else {
            DDLogInfo("Already uploading, ignoring.")
            return
        }

        DDLogInfo("Start uploading, uploadLimitsIndex: \(uploadLimitsIndex), isRetry: \(uploadLimitsIndex > 0)")

        self.isUploading = true
        self.isRetry = isRetry
        self.startTime = Date()
        self.config = config
        self.samplesUploadLimits = samplesUploadLimits
        self.deletesUploadLimits = deletesUploadLimits
        self.uploaderTimeouts = uploaderTimeouts
        self.uploadLimitsIndex = uploadLimitsIndex
        self.uploadAttemptsRemaining = uploadAttemptsRemaining
        self.requestTimeoutInterval = (TimeInterval)(uploaderTimeouts[uploadLimitsIndex])

        // Ensure background task if we're in background
        if UIApplication.shared.applicationState == .background {
            self.beginSamplesUploadBackgroundTask()
        }

        if config.supressUploadDeletes() || self.mode == .HistoricalAll {
            DDLogInfo("Suppressing upload of deletes!")
        } else {
            DDLogInfo("NOT Suppressing upload of deletes!")
        }

        if config.simulateUpload() {
            DDLogInfo("Simulating upload!")
        } else {
            DDLogInfo("NOT Simulating upload!")
        }

        // Cancel any pending tasks (also resets pending state, so we don't get stuck not being able to upload due to early termination or crash wherein the persistent state tracking pending uploads was not reset
        self.uploader.cancelTasks()

        var errorMessage: String?
        var errorCode: Int = 0
        if let serviceAPI = TPUploaderServiceAPI.connector {
            if serviceAPI.currentUploadId == nil {
                errorMessage = "Unable to upload. No upload id available."
                errorCode = -2
            }
        } else {
            errorMessage = "Unable to upload. Service is not configured."
            errorCode = -1
        }
        if !HealthKitManager.sharedInstance.isHealthDataAvailable {
            errorMessage = "Unable to upload. Health data not available."
            errorCode = -3
        }
        if let errorMessage = errorMessage {
            DDLogError(errorMessage)
            let error = NSError(domain: "HealthKitUploadManager", code: errorCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            self.stopUploading(reason: .error(error: error))
            return
        }

        if !isResumable() {
            // Reset reader settings if not resumable
            for reader in readers {
                reader.resetPersistentStateOfReader()
            }
            if mode == .Current {
                settings.resetCurrentUploadSettings()
            } else {
                settings.resetHistoricalUploadSettings()
            }
        }
        resetForNextBatch()
  
        // For initial state, set up date fence posts for anchors, and configure and start readers
        if settings.currentStartDate.value == nil {
            settings.currentStartDate.value = Date().addingTimeInterval(kCurrentStartTimeInPast)
            DDLogVerbose("new currentStartDate: \(settings.currentStartDate.value!)")
        }
        if settings.historicalEndDate.value == nil {
            settings.historicalEndDate.value = Date()
            DDLogVerbose("new historicalEndDate: \(settings.historicalEndDate.value!)")
            // Also set earliest and latest dates here until we discover the range
            settings.historicalEarliestDate.value = settings.historicalEndDate.value
            settings.historicalLatestDate.value = settings.historicalEndDate.value
        }

        if mode == TPUploader.Mode.Current {
            // Observe new samples for Current mode
            DDLogInfo("Start observing samples after starting upload. Mode: \(mode)")
            for reader in readers {
                reader.currentUserId = currentUserId
                reader.sampleReadLimit = samplesUploadLimits[uploadLimitsIndex]
                reader.enableBackgroundDeliverySamples()
                reader.startObservingSamples()
            }
        } else {
            // Kick off reading for historical, if resumable...
            DDLogInfo("Start reading samples after starting upload. Mode: \(mode)")
            // Note: for historical, first step is to figure out sample date range...
            for reader in readers {
                reader.sampleReadLimit = samplesUploadLimits[uploadLimitsIndex]
                reader.currentUserId = currentUserId
                reader.startReading()
            }
        }

        // Mark historical as resumable
        if mode == .HistoricalAll {
            self.settings.historicalIsResumable.value = true
        }

        guard self.isUploading else {
            DDLogInfo("Stopped uploading, don't post TPUploaderNotifications.TurnOnUploader.")
            return
        }

        if !wasUploading {
            postNotifications([TPUploaderNotifications.Updated, TPUploaderNotifications.TurnOnUploader], mode: mode)
        }
    }

    private func postNotifications(_ notificationNames: [String], mode: TPUploader.Mode, reason: TPUploader.StoppedReason? = nil) {
        var uploadInfo : Dictionary<String, Any> = [
            "type" : "All",
            "mode" : mode
        ]
        if let reason = reason {
            uploadInfo["reason"] = reason
        }
        for name in notificationNames {
            NotificationCenter.default.post(Notification(name: Notification.Name(rawValue: name), object: mode, userInfo: uploadInfo))
        }
    }

    func stopUploading(reason: TPUploader.StoppedReason) {
        DDLogVerbose("(\(mode.rawValue))")
        
        guard self.isUploading else {
            if case TPUploader.StoppedReason.interfaceTurnedOff = reason {
                postNotifications([TPUploaderNotifications.Updated, TPUploaderNotifications.TurnOffUploader], mode: mode, reason: reason)
            }
            DDLogInfo("Not currently uploading, ignoring. Mode: \(mode)")
            return
        }
      
        // TODO: upload - for non-resumable historical upload, ideally we probably shouldn't reset the anchor if complete? Ideally we would just pick up new entries with current persisted anchor!? But, then we might want a way to force a reset and do a fresh sync?

        let isConnectedToNetwork = config?.isConnectedToNetwork() ?? false
        var error: NSError?
        if case TPUploader.StoppedReason.error(let stoppedReasonError as NSError) = reason {
            error = stoppedReasonError
        }
        if !isConnectedToNetwork {
            let message = "Upload paused while offline."
            error = NSError(domain: TPUploader.ErrorDomain, code: TPUploader.ErrorCodes.noNetwork.rawValue, userInfo: [NSLocalizedDescriptionKey: message])
        }
        
        var shouldRetry = false
        var attemptsRemainingDelta = -1
        if isConnectedToNetwork && error != nil {
            if error?.domain == TPUploader.ErrorDomain {
              switch error!.code {
                    case 500..<600:
                        shouldRetry = true
                        if !self.didResetUploadAttemptsRemaining {
                            self.didResetUploadAttemptsRemaining = true
                            attemptsRemainingDelta = 2
                        }
                        break
                    default:
                        break
                }
            } else {
                if error!.domain == NSURLErrorDomain {
                    if error!.code != NSURLErrorCancelled {
                        shouldRetry = true
                    }
                } else {
                    // Retry other error domains
                    shouldRetry = true
                }
            }
            if (shouldRetry) {
                shouldRetry = true
                if !self.didResetUploadAttemptsRemaining {
                    self.didResetUploadAttemptsRemaining = true
                    attemptsRemainingDelta = 1
                }
            }
        }
        if shouldRetry && self.uploadLimitsIndex == self.samplesUploadLimits.count - 1 && self.uploadAttemptsRemaining + attemptsRemainingDelta < 1 {
            DDLogInfo("Retry limit reached! Mode: \(mode)")
            shouldRetry = false
        }

        for reader in readers {
            reader.currentUserId = nil
            reader.stopReading()
        }

        self.uploader.cancelTasks()

        if mode == TPUploader.Mode.Current {
            for reader in readers {
                reader.stopObservingSamples()
            }
        }
      
        if shouldRetry {
            self.uploadAttemptsRemaining += attemptsRemainingDelta
            if self.uploadAttemptsRemaining < 1 {
                self.didResetUploadAttemptsRemaining = false
                self.uploadAttemptsRemaining = 1
                self.uploadLimitsIndex = self.uploadLimitsIndex + 1
            }            
            DDLogInfo("Will retry! Mode: \(mode), uploadLimitsIndex: \(uploadLimitsIndex + 1), max uploadLimitsIndex: \(self.samplesUploadLimits.count - 1)")
            DispatchQueue.main.async {
                self.startUploading(config: self.config!, currentUserId: self.config!.currentUserId()!, samplesUploadLimits: self.config!.samplesUploadLimits(), deletesUploadLimits: self.config!.deletesUploadLimits(), uploaderTimeouts: self.config!.uploaderTimeouts(), uploadLimitsIndex: self.uploadLimitsIndex, uploadAttemptsRemaining: self.uploadAttemptsRemaining, isRetry: true)
                self.postNotifications([TPUploaderNotifications.Updated, TPUploaderNotifications.UploadRetry], mode: self.mode, reason: reason)
            }
        } else {
            if mode == .Current {
                DDLogInfo("Stopped uploading, mode: \(mode), \(String(describing: reason)), total samples: \(self.settings.currentTotalSamplesUploadCount.value), total deletes: \(self.settings.currentTotalDeletesUploadCount.value)")
            } else {
                DDLogInfo("Stopped uploading, mode: \(mode), \(String(describing: reason)), total samples: \(self.settings.historicalTotalSamplesUploadCount.value), total deletes: \(self.settings.historicalTotalDeletesUploadCount.value)")
            }

            if mode == .HistoricalAll {
                if case TPUploader.StoppedReason.error = reason {
                    self.settings.historicalIsResumable.value = true
                } else {
                    self.settings.historicalIsResumable.value = false
                }
            }

            self.didResetUploadAttemptsRemaining = false
            self.uploadAttemptsRemaining = 1
            self.isUploading = false
            
            // Log total time for the upload
            // TODO: uploader - also track total retries needed for the total upload. And report that up through to the UI (Debug UI) and log it here
            let seconds = -self.startTime.timeIntervalSinceNow
            DDLogInfo("Total upload finished in: \((Int)(seconds)) seconds")
          
            if mode == .Current {
                self.endSamplesUploadBackgroundTask()
            }

            postNotifications([TPUploaderNotifications.Updated, TPUploaderNotifications.TurnOffUploader], mode: mode, reason: reason)
        }
    }

    func isResumable() -> Bool {
        var result: Bool = false
        if mode == .HistoricalAll {
            result = settings.historicalIsResumable.value
            DDLogInfo("Historical is \(result ? "resumable" : "not resumable")")
        } else {
            result = true
          DDLogInfo("Current is resumable")
        }
        return result
    }

    func resumeUploadingIfResumable(config: TPUploaderConfigInfo, currentUserId: String?, samplesUploadLimits: [Int], deletesUploadLimits: [Int], uploaderTimeouts: [Int], uploadLimitsIndex: Int = 0, uploadAttemptsRemaining: Int = 1) {
        DDLogVerbose("(\(mode.rawValue))")

        if currentUserId != nil && !self.isUploading {
            if mode == TPUploader.Mode.Current {
                // Always OK to resume Current
                self.startUploading(config: config, currentUserId: currentUserId!, samplesUploadLimits: samplesUploadLimits, deletesUploadLimits: deletesUploadLimits, uploaderTimeouts: uploaderTimeouts, uploadLimitsIndex: uploadLimitsIndex, uploadAttemptsRemaining: uploadAttemptsRemaining)
            } else {
                // Only resume HistoricalAll if resumable
                if isResumable() {
                    self.startUploading(config: config, currentUserId: currentUserId!, samplesUploadLimits: samplesUploadLimits, deletesUploadLimits: deletesUploadLimits, uploaderTimeouts: uploaderTimeouts, uploadLimitsIndex: uploadLimitsIndex, uploadAttemptsRemaining: uploadAttemptsRemaining)
                }
            }
        }
    }

    //
    // MARK: - HealthKitSampleUploaderDelegate method
    //

    // NOTE: This is usually called on a background queue, not on main thread
    func sampleUploader(uploader: HealthKitUploader, didCompleteUploadWithError error: Error?, rejectedSamples: [Int]?, requestLog: String?, responseLog: String?) {
        DDLogVerbose("(\(uploader.mode.rawValue))")

        DispatchQueue.main.async {
            DDLogInfo("didCompleteUploadWithError on main thread")

            if let error = error as NSError? {
                // Log the request and response
              if let requestLog = requestLog, let responseLog = responseLog {
                    DDLogInfo(requestLog)
                    DDLogInfo(responseLog)
                }
                            
                // If the service didn't like certain upload samples, remove them and retry...
                if let rejectedSamples = rejectedSamples {
                    // TODO: uploader - should we log (via Rollbar) that we had rejected samples? Presumably backend service is aware and should be logging this itself!?
                    DDLogError("Service rejected \(rejectedSamples.count) samples!")
                    if rejectedSamples.count > 0 {
                        let remainingSamples = self.samplesToUpload
                            .enumerated()
                            .filter {!rejectedSamples.contains($0.offset)}
                            .map{ $0.element}
                        let originalCount = self.samplesToUpload.count
                        let remainingCount = remainingSamples.count
                        let rejectedCount = rejectedSamples.count
                        DDLogVerbose("original count: \(originalCount), remaining count: \(remainingCount), rejected counted: \(rejectedCount)")
                        if originalCount - remainingCount == rejectedCount {
                            self.samplesToUpload = remainingSamples
                            self.tryNextUpload()
                            return
                        }
                    }
                }
                if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
                    let message = "Upload task cancelled. (\(uploader.mode))"
                    DDLogError(message)
                } else {
                    let message = "Upload batch failed, stop reading. (\(uploader.mode)). Error: \(String(describing: error))"
                    DDLogError(message)
                }
                // stop uploading on non-recoverable errors for now...
                self.stopUploading(reason: .error(error: error))
                return
            }
          
            // Success!
          
            DDLogInfo("Successfully uploaded \(self.samplesToUpload.count) samples, \(self.deletesToUpload.count) deletes (\(self.mode)), checking for more in batch")
          
            // If we haven't been stopped, continue the uploading...
            guard self.isUploading else {
                DDLogInfo("Stopping upload...")
                return
            }
  
            for reader in self.readers {
                reader.updateForSuccessfulSamplesUploadInBatch()
            }
            for reader in self.readers {
                reader.updateForSuccessfulDeletesUploadInBatch()
            }
          
            // Gather more uploads for batch
            self.gatherUploadSamples()
            self.gatherUploadDeletes()
            if self.samplesToUpload.count > 0 || self.deletesToUpload.count > 0 {
                DDLogInfo("There are \(self.samplesToUpload.count) more samples and \(self.deletesToUpload.count) more deletes for next upload for batch (\(self.mode))")
                _ = self.tryNextUpload()
                return
            }

            DDLogInfo("Finished uploading batch!")

            // Save overall progress...
            let uploadTime = Date()
            if self.mode == .Current {
                self.settings.lastSuccessfulCurrentUploadTime.value = uploadTime
            }          

            // Let readers persist any progress anchors and update batch stats
            for reader in self.readers {
                reader.updateForFinalSuccessfulUploadInBatch(uploadTime)
            }

            // Update global total samples and deletes counts (across all reader tpes)
            var currentTotalSamplesUploadCount = 0
            var currentTotalDeletesUploadCount = 0
            var currentUploadEarliestSampleTime: Date? = self.settings.currentUploadEarliestSampleTime.value
            var currentUploadLatestSampleTime: Date? = self.settings.currentUploadLatestSampleTime.value
            var historicalTotalSamplesUploadCount = 0
            var historicalTotalDeletesUploadCount = 0
            var historicalUploadEarliestSampleTime: Date? = self.settings.historicalUploadEarliestSampleTime.value
            var historicalUploadLatestSampleTime: Date? = self.settings.historicalUploadLatestSampleTime.value
            var totalDaysHistorical = 0
            var currentDayHistorical = 0
            for reader in self.readers {
                if reader.mode == .Current {
                    currentTotalSamplesUploadCount += reader.readerSettings.totalSamplesUploadCount.value
                    currentTotalDeletesUploadCount += reader.readerSettings.totalDeletesUploadCount.value
                    if let lastSuccessfulUploadEarliestSampleTime = reader.readerSettings.lastSuccessfulUploadEarliestSampleTime.value {
                        if currentUploadEarliestSampleTime == nil || lastSuccessfulUploadEarliestSampleTime < currentUploadEarliestSampleTime! {
                            currentUploadEarliestSampleTime = lastSuccessfulUploadEarliestSampleTime
                        }
                    }
                    if let lastSuccessfulUploadLatestSampleTime = reader.readerSettings.lastSuccessfulUploadLatestSampleTime.value {
                        if currentUploadLatestSampleTime == nil || lastSuccessfulUploadLatestSampleTime > currentUploadLatestSampleTime! {
                            currentUploadLatestSampleTime = lastSuccessfulUploadLatestSampleTime
                        }
                    }
                } else {
                    historicalTotalSamplesUploadCount += reader.readerSettings.totalSamplesUploadCount.value
                    historicalTotalDeletesUploadCount += reader.readerSettings.totalDeletesUploadCount.value
                    totalDaysHistorical = max(totalDaysHistorical, reader.readerSettings.historicalTotalDays.value)
                    currentDayHistorical = max(currentDayHistorical, reader.readerSettings.historicalCurrentDay.value)
                    if let lastSuccessfulUploadEarliestSampleTime = reader.readerSettings.lastSuccessfulUploadEarliestSampleTime.value {
                        if historicalUploadEarliestSampleTime == nil || lastSuccessfulUploadEarliestSampleTime < historicalUploadEarliestSampleTime! {
                            historicalUploadEarliestSampleTime = lastSuccessfulUploadEarliestSampleTime
                        }
                    }
                    if let lastSuccessfulUploadLatestSampleTime = reader.readerSettings.lastSuccessfulUploadLatestSampleTime.value {
                        if historicalUploadLatestSampleTime == nil || lastSuccessfulUploadLatestSampleTime > historicalUploadLatestSampleTime! {
                            historicalUploadLatestSampleTime = lastSuccessfulUploadLatestSampleTime
                        }
                    }
                }
            }
            if self.mode == .Current {
                self.settings.currentTotalSamplesUploadCount.value = currentTotalSamplesUploadCount
                self.settings.currentTotalDeletesUploadCount.value = currentTotalDeletesUploadCount
                self.settings.currentUploadEarliestSampleTime.value = currentUploadEarliestSampleTime
                self.settings.currentUploadLatestSampleTime.value = currentUploadLatestSampleTime
                DDLogInfo("total upload samples: \(currentTotalSamplesUploadCount), deletes: \(currentTotalDeletesUploadCount) (\(self.mode))")
            } else {
                self.settings.historicalTotalSamplesUploadCount.value = historicalTotalSamplesUploadCount
                self.settings.historicalTotalDeletesUploadCount.value = historicalTotalDeletesUploadCount
                self.settings.historicalTotalDays.value = totalDaysHistorical
                self.settings.historicalCurrentDay.value = max(self.settings.historicalCurrentDay.value, currentDayHistorical)
                self.settings.historicalUploadEarliestSampleTime.value = historicalUploadEarliestSampleTime
                self.settings.historicalUploadLatestSampleTime.value = historicalUploadLatestSampleTime
                DDLogInfo("total upload samples: \(historicalTotalSamplesUploadCount), deletes: \(historicalTotalDeletesUploadCount) (\(self.mode))")
            }

            // If we have successfully uploaded, then go back one limit in the limits array
            self.didResetUploadAttemptsRemaining = false
            self.uploadAttemptsRemaining = 1
            if self.uploadLimitsIndex > 0 {
                self.uploadLimitsIndex = max(self.uploadLimitsIndex - 1, 0)
                for reader in self.readers {
                    reader.sampleReadLimit = self.samplesUploadLimits[self.uploadLimitsIndex]
                }
                self.requestTimeoutInterval = (TimeInterval)(self.uploaderTimeouts[self.uploadLimitsIndex])
            }
            if self.isRetry {
                // For successful upload due to retry, just send .UploadRetry (so listeners can maintain state relative to retry attempts/successes
                self.postNotifications([TPUploaderNotifications.Updated, TPUploaderNotifications.UploadRetry], mode: self.mode)
            } else {
                self.postNotifications([TPUploaderNotifications.Updated, TPUploaderNotifications.UploadSuccessful], mode: self.mode)
            }

            self.isRetry = false
            self.checkBackgroundTimeRemaining()
            self.resetForNextBatch()
            if self.isUploading {
                self.checkStartNextSampleReads()
            }
        }
    }
  
    private func beginSamplesUploadBackgroundTask() {
        if self.mode == .Current && self.uploadBackgroundTaskIdentifier == nil {
            self.uploadBackgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(expirationHandler: {
                () -> Void in
                DispatchQueue.main.async {
                    let message = "Stop upload due to background time expired."
                    let error = NSError(domain: TPUploader.ErrorDomain, code: TPUploader.ErrorCodes.backgroundTimeExpired.rawValue, userInfo: [NSLocalizedDescriptionKey: message])
                    DDLogInfo(message)
                    self.stopUploading(reason: .error(error: error))
                    
                    // UIApplication.localNotifyMessage(message)
                }
            })
        }
    }

    private func endSamplesUploadBackgroundTask() {
        if let uploadBackgroundTaskIdentifier = self.uploadBackgroundTaskIdentifier {
            UIApplication.shared.endBackgroundTask(uploadBackgroundTaskIdentifier)
            self.uploadBackgroundTaskIdentifier = nil
        }
    }
  
    private func checkBackgroundTimeRemaining() {
        if self.uploadBackgroundTaskIdentifier != nil {
            let backgroundTimeRemaining = UIApplication.shared.backgroundTimeRemaining
            DDLogInfo("Background time remaining: \(backgroundTimeRemaining) seconds")
            if backgroundTimeRemaining < 5 {
                let message = "Stop upload due to background time expiring."
                let error = NSError(domain: TPUploader.ErrorDomain, code: TPUploader.ErrorCodes.backgroundTimeExpiring.rawValue, userInfo: [NSLocalizedDescriptionKey: message])
                DDLogInfo(message)
                self.stopUploading(reason: .error(error: error))
                self.endSamplesUploadBackgroundTask()
            }
        }
    }

    private var uploadBackgroundTaskIdentifier: UIBackgroundTaskIdentifier?
  
    private func checkStartNextSampleReads() {
        DDLogVerbose("(\(uploader.mode.rawValue))")
        var moreToRead = false
        for reader in readers {
            if reader.moreToRead() {
                moreToRead = true
                reader.startReading()
            }
        }
        // for historical upload, if we are done, enter upload stopped state. Otherwise, reading/uploading continues...
        if self.mode == .HistoricalAll && !moreToRead {
            self.stopUploading(reason: .uploadingComplete)
        }
    }

    //
    // MARK: - HealthKitUploadReaderDelegate methods
    //

    /// Called by each type reader when historical sample range has been determined. The earliest overall sample date is determined, and used for historical progress.
    func uploadReader(reader: HealthKitUploadReader, didUpdateSampleRange startDate: Date, endDate: Date) {
        DDLogVerbose("(\(reader.uploadType.typeName), \(reader.mode.rawValue))")
        if let earliestHistorical = settings.historicalEarliestDate.value {
            if startDate.compare(earliestHistorical) == .orderedAscending {
                settings.historicalEarliestDate.value = startDate
                DDLogVerbose("updated overall earliest sample date from \(earliestHistorical) to \(startDate)")
            }
        } else {
            settings.historicalEarliestDate.value = startDate
            DDLogVerbose("updated overall earliest sample date to \(startDate)")
       }
       if let latestHistorical = settings.historicalLatestDate.value {
           if endDate.compare(latestHistorical) == .orderedDescending {
               settings.historicalLatestDate.value = endDate
               DDLogVerbose("updated overall latest sample date from \(latestHistorical) to \(endDate)")
           }
       } else {
           settings.historicalLatestDate.value = endDate
           DDLogVerbose("updated overall latest sample date to \(endDate)")
      }
    }

    // NOTE: This is a query results handler called from HealthKit, but on main thread
    func uploadReader(reader: HealthKitUploadReader, didStop result: ReaderStoppedReason)
    {
        DDLogVerbose("(\(reader.uploadType.typeName), \(reader.mode.rawValue)) result: \(result)) [main thread]")

        if self.uploader.hasPendingUploadTasks() {
            // ignore new reader samples while we are uploading... could be a result of an observer query restarting a read, or one of the readers finishing while not in the "isReading" state...
            DDLogInfo("hasPendingUploadTasks, ignoring reader callback...")
            return
        }

        var currentReadsComplete = true
        for reader in self.readers {
            if reader.isReading {
                currentReadsComplete = false
            }
        }

        // if all readers are complete, see if we have samples or deletes to upload
        guard currentReadsComplete else {
            DDLogVerbose("wait for other reads to complete...")
            return
        }

        self.gatherUploadSamples()
        self.gatherUploadDeletes()

        guard self.samplesToUpload.count != 0 || self.deletesToUpload.count != 0 else {
            DDLogInfo("No samples or deletes to upload!")
            if self.mode == .HistoricalAll {
                self.stopUploading(reason: .uploadingComplete)
            }
            // for current mode, we keep the observer query active, and leave isUploading true, though all readers will be stopped...
            return
        }
      
        self.tryNextUpload()
    }

    private func tryNextUpload() {
        do {
            DDLogInfo("Start next upload for \(self.samplesToUpload.count) samples, and \(self.deletesToUpload.count) deleted samples. (\(self.mode))")

            // first validate the samples...
            var validatedSamples = [[String: AnyObject]]()
            // Prevent serialization exceptions!
            for sample in self.samplesToUpload {
                //DDLogInfo("Next sample to upload: \(sample)")
                if JSONSerialization.isValidJSONObject(sample) {
                    validatedSamples.append(sample)
                } else {
                    DDLogError("Sample cannot be serialized to JSON!")
                    DDLogError("Sample: \(sample)")
                }
            }
            self.samplesToUpload = validatedSamples
            //print("Next samples to upload: \(samplesToUploadDictArray)")
            DDLogVerbose("Count of samples to upload: \(validatedSamples.count)")
            DDLogInfo("Start next upload for \(self.samplesToUpload.count) samples, and \(self.deletesToUpload.count) deleted samples. (\(self.mode))")

            try self.uploader.startUploadSessionTasks(with: self.samplesToUpload, deletes: self.config!.supressUploadDeletes() || self.mode == .HistoricalAll ? [] : self.deletesToUpload, simulate: config!.simulateUpload(), includeSensitiveInfo: config!.includeSensitiveInfo(), requestTimeoutInterval: self.requestTimeoutInterval)
        } catch let error {
            DDLogError("Failed to prepare upload (\(self.mode)). Error: \(String(describing: error))")
            self.stopUploading(reason: .error(error: error))
        }
    }
}

