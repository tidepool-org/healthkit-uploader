/*
* Copyright (c) 2017-2018, Tidepool Project
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

enum ReaderStoppedReason {
    case error(error: Error)
    case turnedOff
    case withNoNewResults
    case withResults
}

// NOTE: These delegate methods are usually called indirectly from HealthKit or a URLSession delegate, on a background queue, not on main thread
protocol HealthKitUploadReaderDelegate: class {
    func uploadReader(reader: HealthKitUploadReader, didStop result: ReaderStoppedReason)
    func uploadReader(reader: HealthKitUploadReader, didUpdateHistoricalSampleDateRange startDate: Date, endDate: Date)
    func uploadReader(reader: HealthKitUploadReader, didUpdateHistoricalSampleCount count: Int)
}

/// There can be an instance of this class for each mode for each type of upload object.
class HealthKitUploadReader: NSObject {
    
    init(type: HealthKitUploadType, mode: TPUploader.Mode) {
        DDLogVerbose("HealthKitUploadReader init (\(type.typeName),\(mode))")
  
      self.uploadType = type
        self.mode = mode
        sampleReadLimit = 500 // Will be overridden to correspond with upload limits
        self.readerSettings = HKTypeModeSettings(mode: mode, typeName: type.typeName)

        super.init()

        self.reloadQueryAnchor()
    }
    
    weak var delegate: HealthKitUploadReaderDelegate?
    let readerSettings: HKTypeModeSettings
    var queryAnchor: HKQueryAnchor?
    // TODO: uploader - consider having read limits that coordinate better with upload limits so that we don't override. As it is now, the read limit is same as upload limit, but, we have four HK types that we read (four readers), so, we could be reading 4x what we need to, thus potentially buffering more samples per batch, and taking longer to complete the batch before potentially failing and entering retry.
    var sampleReadLimit: Int
    
    private(set) var uploadType: HealthKitUploadType
    private(set) var mode: TPUploader.Mode
    private(set) var isReading = false
    private(set) var isRetry = false
    private(set) var isCountingHistoricalSamples = false
    // Reader may be stopped externally by turning off the interface. Also will stop after each read finishes, when there are no results
    private(set) var stoppedReason: ReaderStoppedReason?

    var config: TPUploaderConfigInfo?
    var currentUserId: String?

    private(set) var sortedSamples: [HKSample] = []
    private(set) var earliestSampleTime = Date.distantFuture
    private(set) var latestSampleTime = Date.distantPast
    private(set) var newOrDeletedSamplesWereDelivered = false
    private(set) var deletedSamples = [HKDeletedObject]()
    private(set) var earliestUploadSampleTime: Date?    // only needed for stats reporting
    private(set) var latestUploadSampleTime: Date?      // also needed for historical query range determination
    private(set) var uploadSampleCount = 0
    private(set) var uploadDeleteCount = 0
    
    func popNextSample() -> HKSample? {
        if let sample = sortedSamples.popLast() {
            if earliestUploadSampleTime == nil {
                // first sample sets both dates
                earliestUploadSampleTime = sample.startDate
                latestUploadSampleTime = sample.startDate
            } else {
                // for historical, we are going backwards chronologically...
                earliestUploadSampleTime = sample.startDate
            }
            return sample
        }
        return nil
    }

    func nextSampleDate() -> Date? {
        return sortedSamples.last?.startDate
    }

    func sampleToUploadDict(_ sample: HKSample) -> [String: AnyObject]? {
        let sampleToDict = uploadType.prepareDataForUpload(sample)
        if sampleToDict != nil {
            uploadSampleCount += 1
        }
        return sampleToDict
    }
      
    func resetPersistentStateOfReader() {
        DDLogVerbose("HealthKitUploadReader (\(uploadType.typeName), \(mode.rawValue))")
        stopObservingSamples() // just in case...
        readerSettings.resetAllReaderKeys()
        readerSettings.resetAllStatsKeys()
        resetReadBuffers()
        resetSamplesUploadStats()
        resetDeletesUploadStats()
        resetSamplesAttemptStats()
        resetDeletesAttemptStats()
        readerSettings.startDateHistoricalSamples.value = nil
        readerSettings.endDateHistoricalSamples.value = nil
        readerSettings.totalSamplesCount.value = 0
    }
  
    func resetReadBuffers() {
        self.sortedSamples = []
        self.deletedSamples = []
    }

    func resetSamplesUploadStats() {
        DDLogVerbose("HealthKitUploadReader (\(self.uploadType.typeName),\(self.mode))")
        earliestUploadSampleTime = nil
        latestUploadSampleTime = nil
        readerSettings.resetSamplesAttemptStats()
        readerSettings.resetSamplesBatchStats()
    }

    func resetDeletesUploadStats() {
        DDLogVerbose("HealthKitUploadReader (\(self.uploadType.typeName),\(self.mode))")
        readerSettings.resetDeletesAttemptStats()
        readerSettings.resetDeletesBatchStats()
    }

    func resetSamplesAttemptStats() {
        readerSettings.resetSamplesAttemptStats()
        uploadSampleCount = 0
    }
  
    func resetDeletesAttemptStats() {
        readerSettings.resetDeletesAttemptStats()
        uploadDeleteCount = 0
    }

    func reloadQueryAnchor() {
      self.queryAnchor = readerSettings.queryAnchor.value
    }

    func reportNextUploadSamplesStatsAtTime(_ uploadTime: Date) {
        if uploadSampleCount > 0 {
            guard let earliestSample = earliestUploadSampleTime, let latestSample = latestUploadSampleTime else {
                return
            }
            readerSettings.updateForSamplesUploadAttempt(sampleCount: uploadSampleCount, uploadAttemptTime: uploadTime, earliestSampleTime: earliestSample, latestSampleTime: latestSample)
        }
    }

    func reportNextUploadDeletesStatsAtTime(_ uploadTime: Date) {
        if uploadDeleteCount > 0 {
            readerSettings.updateForDeletesUploadAttempt(deleteCount: uploadDeleteCount, uploadAttemptTime: uploadTime)
        }
    }

    func updateForSuccessfulSamplesUploadInBatch() {
        readerSettings.updateForSuccessfulSamplesUploadInBatch()
    }

    func updateForSuccessfulDeletesUploadInBatch() {
        readerSettings.updateForSuccessfulDeletesUploadInBatch()
    }

    func updateForFinalSuccessfulUploadInBatch(_ uploadTime: Date) {
        DDLogVerbose("updateForFinalSuccessfulUploadInBatch (\(self.uploadType.typeName),\(self.mode))")
        readerSettings.updateForFinalSuccessfulUploadInBatch(lastSuccessfulUploadTime: uploadTime)
        // Note: only persist query anchor when all queried samples have been successfully uploaded! Otherwise, if app quits with buffered samples, it will miss those on a new query. This does mean that in this case the same samples may be uploaded to the service, but they will be handled by the service's de-duplication logic.
        self.persistQueryAnchor()
    }
    
    func moreToRead() -> Bool {
        if let stoppedReason = self.stoppedReason, case ReaderStoppedReason.withResults = stoppedReason {
            return true
        }
        return false
    }
    
    func nextDeletedSampleDict() -> [String: AnyObject]? {
        if let nextDelete = deletedSamples.popLast() {
            uploadDeleteCount += 1
            return uploadType.prepareDataForDelete(nextDelete)
        }
        return nil
    }
    
    func handleNewSamples(_ newSamples: [HKSample]?, deletedSamples: [HKDeletedObject]?) {
        DDLogVerbose("newSamples: \(String(describing: newSamples?.count)), deletedSamples: \(String(describing: deletedSamples?.count)) (\(self.uploadType.typeName),\(self.mode))")
        self.newOrDeletedSamplesWereDelivered = false
        self.earliestSampleTime = Date.distantFuture
        self.latestSampleTime = Date.distantPast
        
        if let newSamples = newSamples, newSamples.count > 0 {
            var unsortedSamples = self.sortedSamples
            unsortedSamples.append(contentsOf: newSamples)
            // Sort by sample date
            self.sortedSamples = unsortedSamples.sorted(by: {x, y in
                return x.startDate.compare(y.startDate) == .orderedAscending
            })
            if let firstSample = sortedSamples.first {
                self.earliestSampleTime = firstSample.startDate
            }
            if let lastSample = sortedSamples.last {
                self.latestSampleTime = lastSample.startDate
            }
            if newSamples.count > 0 {
                self.newOrDeletedSamplesWereDelivered = true
            }
        }
        
        if deletedSamples != nil && deletedSamples!.count > 0 {
            self.newOrDeletedSamplesWereDelivered = true
            self.deletedSamples.insert(contentsOf: deletedSamples!, at: self.deletedSamples.endIndex)
        }
    }  
    
    func isFresh() -> Bool {
        let result = readerSettings.queryAnchor.value == nil
        DDLogVerbose("isFresh: \(result) (\(self.uploadType.typeName),\(self.mode))")
        return result
    }

    func startReading(isRetry: Bool) {
        DDLogVerbose("HealthKitUploadReader (\(self.uploadType.typeName),\(self.mode))")
        
        guard !self.isReading else {
            DDLogVerbose("Ignoring request to start reading samples, already reading samples")
            return
        }
        
        self.stoppedReason = nil
        self.isReading = true
        self.isRetry = isRetry
        self.readMore()
    }
    
    private func persistQueryAnchor() {
        DDLogVerbose("persistQueryAnchor (\(self.uploadType.typeName),\(self.mode))")
        readerSettings.queryAnchor.value = self.queryAnchor
    }
    
    func stopReading() {
        DDLogVerbose("HealthKitUploadReader (\(self.uploadType.typeName),\(self.mode))")

        guard self.isReading || self.isCountingHistoricalSamples else {
            DDLogInfo("Not currently reading or counting historical samples, ignoring. Mode: \(self.mode)")
            return
        }
        self.stopReading(.turnedOff)
    }
    
    private func stopReading(_ reason: ReaderStoppedReason) {
        DDLogVerbose("HealthKitUploadReader reason: \(reason)) (\(self.uploadType.typeName),\(self.mode))")
        guard self.isReading || self.isCountingHistoricalSamples else {
            DDLogInfo("Currently turned off, ignoring. Mode: \(self.mode)")
            return
        }
        self.stoppedReason = reason
        self.isReading = false
        self.isCountingHistoricalSamples = false
        self.delegate?.uploadReader(reader: self, didStop: reason)
    }
    
    func readMore() {
        DDLogInfo("(\(uploadType.typeName), \(mode.rawValue))")
        
        // If we have buffered samples, no need to read more
        let bufferedSamplesCount = sortedSamples.count
        if bufferedSamplesCount > 0 {
            if bufferedSamplesCount >= sampleReadLimit {
                // we still have sampleReadLimit or more samples, so no need to read more...
                self.stopReading(.withResults)
                return
            }
        }
        
        // note the anchor
        DDLogVerbose("queryAnchor: \(String(describing: self.queryAnchor)) (\(uploadType.typeName), \(mode.rawValue))")
        if (self.queryAnchor == nil) {
            DDLogInfo("no anchor, starting fresh (\(uploadType.typeName), \(mode.rawValue))");
        }

        let globalSettings = HKGlobalSettings.sharedInstance
        guard let fenceDate = (mode == .Current ? globalSettings.currentStartDate.value : globalSettings.historicalEndDate.value) else {
            let message = "Stop upload due to missing global fence date."
            let error = NSError(domain: TPUploader.ErrorDomain, code: TPUploader.ErrorCodes.noFenceDate.rawValue, userInfo: [NSLocalizedDescriptionKey: message])
            DDLogInfo(message)
            self.stopReading(.error(error: error))
            return
        }
                
        let start = (mode == .Current ? fenceDate : Date.distantPast)
        let end = (mode == .Current ? Date.distantFuture : fenceDate)
        DDLogInfo("using query start: \(start), end: \(end), sampleReadLimit: \(sampleReadLimit)")
        self.readSamplesFromAnchorForType(self.uploadType, start: start, end: end, anchor: self.queryAnchor, limit: sampleReadLimit, resultsHandler: self.readResultsHandler)
    }

    // MARK: Private
    
    func startCountingHistoricalSamples() {
        DDLogVerbose("HealthKitUploadReader (\(self.uploadType.typeName),\(self.mode))")
      
        self.stoppedReason = nil
        self.isCountingHistoricalSamples = true

        let sampleType = uploadType.hkSampleType()!
        self.findHistoricalSampleDateRange(sampleType: sampleType) {
            (error: NSError?, startDate: Date?, endDate: Date?) in
            
            DispatchQueue.main.async {
                DDLogVerbose("HealthKitUploadReader [Main] error: \(String(describing: error)) start: \(String(describing: startDate)) end: \(String(describing: endDate)) (\(self.uploadType.typeName),\(self.mode))")
                if error == nil, let startDate = startDate, let endDate = endDate {
                    self.readerSettings.updateForHistoricalSampleDateRange(startDate: startDate, endDate: endDate)
                    self.delegate?.uploadReader(reader: self, didUpdateHistoricalSampleDateRange: startDate, endDate: endDate)

                    let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: [])
                    self.countHistoricalSamples(sampleType: sampleType, anchor: nil, predicate: predicate)
                } else {
                    // Set start and end to distantFuture date, to mark that findHistoricalSampleDateRange has been run, and show that no historical samples are available for this type.
                    let noSamplesDate = Date.distantFuture
                    self.readerSettings.updateForHistoricalSampleDateRange(startDate: noSamplesDate, endDate: noSamplesDate)
                    self.readerSettings.updateForHistoricalSampleCount(0)
                    if let error = error {
                        DDLogError("Failed to update historical samples date range, error: \(error)")
                        self.stopReading(.error(error: error))
                    } else {
                        DDLogVerbose("no historical samples found !")
                        self.stopReading(.withNoNewResults)
                    }
                }
            }
        }
    }
    
    // NOTE: This is a HealthKit results handler, not called on main thread
    private func readResultsHandler(_ error: NSError?, newSamples: [HKSample]?, deletedSamples: [HKDeletedObject]?, newAnchor: HKQueryAnchor?) {
        DispatchQueue.main.async {
            
            var debugStr = ""
            if let newSamples = newSamples {
                debugStr = "newSamples: \(newSamples.count)"
            }
            if let deletedSamples = deletedSamples {
                debugStr += " deletedSamples: \(deletedSamples.count)"
            }
            debugStr += " sampleReadLimit: \(self.sampleReadLimit)"
          
            DDLogVerbose("(\(self.uploadType.typeName), \(self.mode.rawValue)) \(debugStr)")
            if error != nil {
                DDLogError("Error: \(String(describing: error!))")
            }
            
            guard self.isReading else {
                DDLogInfo("Not currently reading, ignoring")
                return
            }
            
            guard let _ = self.currentUserId else {
                DDLogInfo("No logged in user, unable to upload")
                return
            }
            
            var stoppedReason: ReaderStoppedReason = .withResults
            if error == nil {
                // update our anchor after a successful read. It will be persisted after all samples have been uploaded...
                self.queryAnchor = newAnchor
                self.handleNewSamples(newSamples, deletedSamples: deletedSamples)
                if !self.newOrDeletedSamplesWereDelivered {
                    DDLogVerbose("stop due to no results!")
                    stoppedReason = .withNoNewResults
                } else {
                    self.config?.logData(mode: self.mode, phase: HKDataLogPhase.read, isRetry: self.isRetry, samples: newSamples, deletes: deletedSamples)
                }
            } else {
                stoppedReason = .error(error: error!)
                DDLogError("(\(self.uploadType.typeName), mode: \(self.mode.rawValue)) Error reading most recent samples: \(String(describing: error))")
            }
            // enter appropriate stopped state
            self.stopReading(stoppedReason)
        }
    }
    
    //
    // MARK: - Health Store reading methods
    //
    
    /// Uses an HKAnchoredObjectQuery to get samples. The fences for current and historical are opposite
    func readSamplesFromAnchorForType(_ uploadType: HealthKitUploadType, start: Date, end: Date, anchor: HKQueryAnchor?, limit: Int, resultsHandler: @escaping ((NSError?, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?) -> Void))
    {
        DDLogVerbose("HealthKitUploadReader (\(self.uploadType.typeName),\(self.mode))")
        let hkManager = HealthKitManager.sharedInstance
         guard hkManager.isHealthDataAvailable else {
            DDLogError("Unexpected HealthKitManager call when health data not available")
            return
        }
 
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let sampleType = uploadType.hkSampleType()!
        let sampleQuery = HKAnchoredObjectQuery(type: sampleType,
                                                predicate: predicate,
                                                anchor: anchor,
                                                limit: limit) {
                                                    (query, newSamples, deletedSamples, newAnchor, error) -> Void in
                                                    
                                                    if error != nil {
                                                        DDLogError("Error reading samples: \(String(describing: error))")
                                                    }
                                                    
                                                    resultsHandler((error as NSError?), newSamples, deletedSamples, newAnchor)
        }
        hkManager.healthStore?.execute(sampleQuery)
    }
    
    func findHistoricalSampleDateRange(sampleType: HKSampleType, completion: @escaping (_ error: NSError?, _ startDate: Date?, _ endDate: Date?) -> Void)
    {
        DDLogVerbose("HealthKitUploadReader (\(self.uploadType.typeName),\(self.mode))")
        let hkManager = HealthKitManager.sharedInstance

        var earliestSampleDate: Date? = nil
        var latestSampleDate: Date? = nil
        
        let globalSettings = HKGlobalSettings.sharedInstance
        var endDate = Date.distantFuture
        if let historicalEndDate = globalSettings.historicalEndDate.value {
            endDate = historicalEndDate
            DDLogVerbose("search end date: \(endDate)")
        } else {
            DDLogError("end date should already be set!")
        }

        let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: endDate, options: [])
        let startDateSortDescriptor = NSSortDescriptor(key:HKSampleSortIdentifierStartDate, ascending: true)
        let endDateSortDescriptor = NSSortDescriptor(key:HKSampleSortIdentifierStartDate, ascending: false)
        
        // Kick off query to find startDate
        let startDateSampleQuery = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: 1, sortDescriptors: [startDateSortDescriptor]) {
            (query: HKSampleQuery, samples: [HKSample]?, error: Error?) -> Void in
            
            DDLogVerbose("startDateSampleQuery: error: \(String(describing: error)) sample count: \(String(describing: samples?.count)) (\(self.uploadType.typeName),\(self.mode))")
            if error == nil && samples != nil {
                // Get date of oldest sample
                if samples!.count > 0 {
                    earliestSampleDate = samples![0].startDate
                }
                
                // Kick off query to find endDate
                let endDateSampleQuery = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: 1, sortDescriptors: [endDateSortDescriptor]) {
                    (query: HKSampleQuery, samples: [HKSample]?, error: Error?) -> Void in
                    
                    DDLogVerbose("endDateSampleQuery: error: \(String(describing: error)) sample count: \(String(describing: samples?.count)) (\(self.uploadType.typeName),\(self.mode))")
                    if error == nil && samples != nil && samples!.count > 0 {
                        latestSampleDate = samples![0].startDate
                      
                        DDLogInfo("findHistoricalSampleDateRange complete for \(self.uploadType.typeName), \(String(describing: earliestSampleDate))) to \(String(describing: latestSampleDate))")
                        completion(nil, earliestSampleDate, latestSampleDate)
                    } else {
                        completion((error as NSError?), earliestSampleDate, latestSampleDate)
                    }
                }
                hkManager.self.healthStore?.execute(endDateSampleQuery)
            } else {
                completion((error as NSError?), earliestSampleDate, latestSampleDate)
            }
        }
        hkManager.healthStore?.execute(startDateSampleQuery)
    }

    func countHistoricalSamples(sampleType: HKSampleType, anchor: HKQueryAnchor?, predicate: NSPredicate)
    {
        guard self.isCountingHistoricalSamples else {
            return
        }

        DDLogVerbose("HealthKitUploadReader (\(self.uploadType.typeName),\(self.mode))")
        let hkManager = HealthKitManager.sharedInstance
        let limit = 50000
        let countQuery = HKAnchoredObjectQuery(
          type: sampleType,
          predicate: predicate,
          anchor: anchor,
          limit: limit) {
              (query, newSamples, deletedSamples, newAnchor, error) -> Void in
              if error == nil {
                  var newSamplesCount = 0
                  if newSamples != nil {
                      newSamplesCount = newSamples!.count
                  }
                  if newSamplesCount > 0 {
                      DispatchQueue.main.async {
                        self.readerSettings.updateForHistoricalSampleCount(newSamplesCount)
                        self.delegate?.uploadReader(reader: self, didUpdateHistoricalSampleCount: newSamplesCount)

                        self.countHistoricalSamples(sampleType: sampleType, anchor: newAnchor, predicate: predicate)
                      }
                  } else {
                    self.stopReading(self.readerSettings.historicalTotalSamplesCount.value > 0 ? .withResults : .withNoNewResults)
                  }
              } else {
                DDLogError("Failed to update historical samples count, error: \(String(describing: error))")
                  self.stopReading(.error(error: error!))
              }
          }
        hkManager.healthStore?.execute(countQuery)
    }

    // MARK: Observation
    
    func startObservingSamples() {
        DDLogVerbose("HealthKitUploadReader startObservingSamples(\(self.uploadType.typeName),\(self.mode))")
        let hkManager = HealthKitManager.sharedInstance
        guard hkManager.isHealthDataAvailable else {
            DDLogError("Unexpected HealthKitManager call when health data not available")
            return
        }
        
        if uploadType.sampleObservationQuery != nil {
            hkManager.healthStore?.stop(uploadType.sampleObservationQuery!)
            uploadType.sampleObservationQuery = nil
        }
        
        let sampleType = uploadType.hkSampleType()!
        uploadType.sampleObservationQuery = HKObserverQuery(sampleType: sampleType, predicate: nil) {
            (query, observerQueryCompletion, error) in
            
            DDLogVerbose("Observation query called (\(self.uploadType.typeName), \(self.mode.rawValue))")
            
            if error != nil {
                DDLogError("HealthKit observation error \(String(describing: error))")
            }

            // Per HealthKit docs: Calling this block tells HealthKit that you have successfully received the background data. If you do not call this block, HealthKit continues to attempt to launch your app using a back off algorithm. If your app fails to respond three times, HealthKit assumes that your app cannot receive data, and stops sending you background updates
            DDLogVerbose("observerQueryCompletion called (\(self.uploadType.typeName), \(self.mode.rawValue)) ")

            observerQueryCompletion()

            // TODO: background uploader - moved this after the observerQueryCompletion call, at least during debugging, so system doesn't turn off calls...
            self.sampleObservationHandler(error as NSError?)
            
        }
        hkManager.healthStore?.execute(uploadType.sampleObservationQuery!)
    }
    
    // NOTE: This is a query observer handler called from HealthKit, not on main thread
    private func sampleObservationHandler(_ error: NSError?) {
        DDLogVerbose("sampleObservationHandler error: \(String(describing: error)) (\(self.uploadType.typeName), \(self.mode.rawValue))")
        
        DispatchQueue.main.async {
            DDLogInfo("sampleObservationHandler [Main] (\(self.uploadType.typeName), \(self.mode.rawValue))")
            
            guard self.mode == .Current else {
                DDLogError("uploadObservationHandler called on historical reader!")
                return
            }
            
            guard !self.isReading else {
                DDLogInfo("currently reading, ignore observer query!")
                return
            }
            
            guard error == nil else {
                DDLogError("sampleObservationQuery error: \(String(describing: error))")
                return
            }
            
            // kick off a read to get the new samples...
            // TODO: but not if we haven't reached the end of initial .Current upload?
            DDLogInfo("sampleObservationQuery startReading!")
            self.startReading(isRetry: false)
        }
    }

    func stopObservingSamples() {
        DDLogVerbose("HealthKitUploadReader (\(self.uploadType.typeName),\(self.mode))")

        let hkManager = HealthKitManager.sharedInstance
        guard hkManager.isHealthDataAvailable else {
            DDLogError("Unexpected HealthKitManager call when health data not available")
            return
        }
        
        if uploadType.sampleObservationQuery != nil {
            hkManager.healthStore?.stop(uploadType.sampleObservationQuery!)
            uploadType.sampleObservationQuery = nil
        }
    }
    
    // MARK: Background delivery
    
    // Note: this only works on a device; on the simulator, the app will not be called while it is in the background.
    func enableBackgroundDeliverySamples() {
        DDLogVerbose("HealthKitUploadReader (\(self.uploadType.typeName),\(self.mode))")

        let hkManager = HealthKitManager.sharedInstance
        guard hkManager.isHealthDataAvailable else {
            DDLogError("Unexpected HealthKitManager call when health data not available")
            return
        }
        
        if !uploadType.sampleBackgroundDeliveryEnabled {
            hkManager.healthStore?.enableBackgroundDelivery(
                for: uploadType.hkSampleType()!,
                frequency: HKUpdateFrequency.immediate) {
                    success, error -> Void in
                    if error == nil {
                        self.uploadType.sampleBackgroundDeliveryEnabled = true
                        DDLogInfo("Enabled (\(self.uploadType.typeName), \(self.mode.rawValue))")
                    } else {
                        DDLogError("Error enabling background delivery: \(String(describing: error)) (\(self.uploadType.typeName), \(self.mode.rawValue))")
                    }
            }
        }
    }
}
