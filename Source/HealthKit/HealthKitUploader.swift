/*
* Copyright (c) 2016, Tidepool Project
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

protocol HealthKitSampleUploaderDelegate: class {
    func sampleUploader(uploader: HealthKitUploader, didCompleteUploadWithError error: Error?, rejectedSamples: [Int]?, requestLog: String?, responseLog: String?)
}

class HealthKitUploader: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {
    init(_ mode: TPUploader.Mode) {
        DDLogVerbose("mode: \(mode.rawValue)")

        self.mode = mode
        super.init()

        self.ensureUploadSession()
    }

    private(set) var mode: TPUploader.Mode
    var requestTimeoutInterval: TimeInterval = 60
    weak var delegate: HealthKitSampleUploaderDelegate?
    private let settings = HKGlobalSettings.sharedInstance

    func hasPendingUploadTasks() -> Bool {
        let setting = mode == .Current ? settings.hasPendingCurrentUploads : settings.hasPendingHistoricalUploads
        return setting.value
    }

    private var lastUploadSamplePostBody: Data?
    private var lastDeleteSamplePostBody: Data?
    private var lastDeleteSamplePostBodyUrl: URL?
    private var includeSensitiveInfo: Bool = false

    // NOTE: This is called from a query results handler, not on main thread
  func startUploadSessionTasks(with samples: [[String: AnyObject]], deletes: [[String: AnyObject]], simulate: Bool, includeSensitiveInfo: Bool, requestTimeoutInterval: TimeInterval) throws {
        DDLogVerbose("mode: \(mode.rawValue)")
      
        self.includeSensitiveInfo = includeSensitiveInfo
        self.requestTimeoutInterval = requestTimeoutInterval

        // Prepare POST files for upload. Fine to do this on background thread (Upload tasks from NSData are not supported in background sessions, so this has to come from a file, at least if we are in the background).
        // May be nil if no samples to upload
        //DDLogVerbose("samples to upload: \(samples)")
        let (batchSamplesPostBodyUrl, samplePostBody) = try createPostBodyForBatchSamplesUpload(samples)
        lastUploadSamplePostBody = samplePostBody

        // May be nil if no samples to delete
        let (deleteSampleBodyUrl, deletePostBody) = try createPostBodyForBatchSamplesDelete(deletes)
        lastDeleteSamplePostBody = deletePostBody
        lastDeleteSamplePostBodyUrl = deleteSampleBodyUrl

        DispatchQueue.main.async {
            DDLogInfo("(mode: \(self.mode.rawValue)) [main]")
            if simulate {
                DDLogInfo("SKIPPING UPLOAD!")
                self.delegate?.sampleUploader(uploader: self, didCompleteUploadWithError: nil, rejectedSamples: nil, requestLog: nil, responseLog: nil)
                return
            }

            guard let uploadSession = self.uploadSession else {
                let message = "Unable to start upload tasks, upload session does not exist"
                let error = NSError(domain: TPUploader.ErrorDomain, code: TPUploader.ErrorCodes.noSession.rawValue, userInfo: [NSLocalizedDescriptionKey: message])
                DDLogError(message)
                self.delegate?.sampleUploader(uploader: self, didCompleteUploadWithError: error, rejectedSamples: nil, requestLog: nil, responseLog: nil)
                return
            }

            // Default error message...
            var message: String?

            // Create upload task if there are uploads to do...
            if let samplePostBody = self.lastUploadSamplePostBody {
                do {
                    var request = try TPUploaderServiceAPI.connector!.makeDataUploadRequest("POST")
                    if self.mode == .HistoricalAll {
                        request.timeoutInterval = self.requestTimeoutInterval
                        DDLogInfo("requestTimeout: \(self.requestTimeoutInterval)")
                    }
                    self.setPendingUploadsState(uploadTaskIsPending: true)
                    let uploadTask: URLSessionUploadTask = {
                        if let batchSamplesPostBodyUrl = batchSamplesPostBodyUrl {
                            return uploadSession.uploadTask(with: request, fromFile: batchSamplesPostBodyUrl)
                        } else {
                            return uploadSession.uploadTask(with: request, from: samplePostBody)
                        }
                    }()
                    uploadTask.taskDescription = self.prefixedLocalId(self.uploadSamplesTaskDescription)
                    DDLogInfo("((self.mode.rawValue)) Created samples upload task: \(uploadTask.taskIdentifier)")
                    uploadTask.resume()
                    return
                } catch {
                    message = "Failed to create upload POST url"
                }
            }
            // Otherwise check for deletes...
            else if self.startDeleteTaskInSession(uploadSession) == true {
                // delete task started successfully
                return
            }

            self.setPendingUploadsState(uploadTaskIsPending: false)
            if message != nil {
              let settingsError = NSError(domain: TPUploader.ErrorDomain, code: TPUploader.ErrorCodes.noUploadUrl.rawValue, userInfo: [NSLocalizedDescriptionKey: message!])
                DDLogError(message!)
              self.delegate?.sampleUploader(uploader: self, didCompleteUploadWithError: settingsError, rejectedSamples: nil, requestLog: nil, responseLog: nil)
            } else {
                // No uploads or deletes found (probably due to filtered bad values)
                self.delegate?.sampleUploader(uploader: self, didCompleteUploadWithError: nil, rejectedSamples: nil, requestLog: nil, responseLog: nil)
            }
        }
    }

    func startDeleteTaskInSession(_ session: URLSession) -> Bool {
        if let deleteSamplePostBody = lastDeleteSamplePostBody
        {
            self.setPendingUploadsState(uploadTaskIsPending: true)
            do {
                var deleteSamplesRequest = try TPUploaderServiceAPI.connector!.makeDataUploadRequest("DELETE")
                if mode == .HistoricalAll {
                    deleteSamplesRequest.timeoutInterval = self.requestTimeoutInterval
                    DDLogInfo("requestTimeout: \(self.requestTimeoutInterval)")
                }
                self.setPendingUploadsState(uploadTaskIsPending: true)
              
                let deleteTask: URLSessionUploadTask = {
                    if let deleteSamplePostBodyUrl = lastDeleteSamplePostBodyUrl {
                        return session.uploadTask(with: deleteSamplesRequest, fromFile: deleteSamplePostBodyUrl)
                    } else {
                        return session.uploadTask(with: deleteSamplesRequest, from: deleteSamplePostBody)
                    }
                }()

                deleteTask.taskDescription = self.prefixedLocalId(self.deleteSamplesTaskDescription)
                DDLogInfo("(\(self.mode.rawValue)) Created samples delete task: \(deleteTask.taskIdentifier)")
                deleteTask.resume()
                return true
           } catch {
                DDLogError("Failed to create upload DELETE Url!")
           }
        }
        return false
    }

    func cancelTasks() {
        DDLogVerbose("mode: \(mode.rawValue)")

        if self.uploadSession == nil {
            self.setPendingUploadsState(uploadTaskIsPending: false)
        } else {
            self.uploadSession!.getTasksWithCompletionHandler { (dataTasks, uploadTasks, downloadTasks) -> Void in
                if uploadTasks.count > 0 {
                    DDLogInfo("(\(self.mode.rawValue)) Canceling \(uploadTasks.count) tasks")
                    for uploadTask in uploadTasks {
                        DDLogInfo("Canceling task: \(uploadTask.taskIdentifier)")
                        uploadTask.cancel()
                    }
                } else {
                    self.setPendingUploadsState(uploadTaskIsPending: false)
                }
            }
        }
    }

    // MARK: URLSessionTaskDelegate
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DDLogVerbose("mode: \(mode.rawValue)")

        var message = ""
        let taskDescr = task.taskDescription ?? ""
        if let error = error {
            message = "Upload task failed: \(taskDescr), with error: \(error), id: \(task.taskIdentifier)"
        } else {
            message = "Upload task completed: \(taskDescr), id: \(task.taskIdentifier)"
        }
        DDLogInfo(message)
        //UIApplication.localNotifyMessage(message)

        var httpError: NSError?
        var rejectedSamples: [Int]?
        if let response = task.response as? HTTPURLResponse {
            if !(200 ... 299 ~= response.statusCode) {
                let message = "HTTP error on upload: \(response.statusCode)"
                var responseMessage: String?
                if let lastData = lastData  {
                    responseMessage = String(data: lastData, encoding: .utf8)
                    if response.statusCode == 400 {
                        do {
                            let json = try JSONSerialization.jsonObject(with: lastData, options: [])
                            if let jsonDict = json as? [String: Any] {
                                rejectedSamples = parseErrResponse(jsonDict)
                            }
                        } catch {
                            DDLogError("Unable to parse response message as dictionary!")
                        }
                    }
                }
                DDLogError(message)
                if let responseMessage = responseMessage {
                    DDLogInfo("response message: \(responseMessage)")
                }
                if let postBody = lastUploadSamplePostBody {
                    if let postBodyJson = String(data: postBody, encoding: .utf8) {
                        DDLogInfo("failed upload samples: \(postBodyJson)")
                    } else {
                        DDLogInfo("failed upload samples: ...")
                    }
                } else if let postBody = lastDeleteSamplePostBody {
                    if let postBodyJson = String(data: postBody, encoding: .utf8) {
                        DDLogInfo("failed delete samples: \(postBodyJson)")
                    } else {
                        DDLogInfo("failed delete samples: ...")
                    }
                }
                httpError = NSError(domain: TPUploader.ErrorDomain, code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
            }
        }

        // Log request and response for uploads
        var requestLog: String?
        var responseLog: String?
        let logRequestAndResponse = self.includeSensitiveInfo && (error != nil || httpError != nil)
        if logRequestAndResponse {
            if let request = task.originalRequest {
                let body = lastUploadSamplePostBody ?? lastDeleteSamplePostBody ?? request.httpBody
                requestLog = HealthKitUploader.createRequestLog(request: request, body: body)
                responseLog = HealthKitUploader.createResponseLog(data: lastData, response: task.response as? HTTPURLResponse, error: task.error)
            }
        }

        if error != nil || httpError != nil {
            self.setPendingUploadsState(uploadTaskIsPending: false)
            self.delegate?.sampleUploader(uploader: self, didCompleteUploadWithError: error ?? httpError, rejectedSamples: rejectedSamples, requestLog: requestLog, responseLog: responseLog)
            lastUploadSamplePostBody = nil
            lastDeleteSamplePostBody = nil
            lastDeleteSamplePostBodyUrl = nil
            return
        }
      
        if lastUploadSamplePostBody != nil {
            lastUploadSamplePostBody = nil
        } else if lastDeleteSamplePostBody != nil {
            lastDeleteSamplePostBody = nil
            lastDeleteSamplePostBodyUrl = nil
        }

        // See if there are any deletes to do, and resume task to do them if so. Deletes always follow samples, if there were any samples to upload
        if task.taskDescription == prefixedLocalId(self.uploadSamplesTaskDescription) {
            if self.startDeleteTaskInSession(session) == true {
                return
            }
        }
        
        // Success, we're done with both samples and deletes
        lastUploadSamplePostBody = nil
        lastDeleteSamplePostBody = nil
        lastDeleteSamplePostBodyUrl = nil
        self.setPendingUploadsState(uploadTaskIsPending: false)
        self.delegate?.sampleUploader(uploader: self, didCompleteUploadWithError: nil, rejectedSamples: nil, requestLog: requestLog, responseLog: responseLog)
    }

    private class func createRequestLog(request: URLRequest, body: Data?) -> String {
        // Log request as curl so we can replay to test
        var log = ""
        if let absoluteUrlString = request.url?.absoluteString, let body = body {
            log = "curl -v \(absoluteUrlString)"
            for (key,value) in request.allHTTPHeaderFields ?? [:] {
                log += " -H \"\(key): \(value)\""
            }
            let bodyString = NSString(data: body, encoding: String.Encoding.utf8.rawValue) ?? "Not utf8!";
            log += " -d '\(bodyString)' "
        } else {
            log = "curl: Failed to get url or body!"
        }
        return log
    }

    private class func createResponseLog(data: Data?, response: HTTPURLResponse?, error: Error?) -> String {
        var log = "------------------------\n"
        if let statusCode =  response?.statusCode {
            log += "HTTP \(statusCode)\n"
        }
        for (key,value) in response?.allHeaderFields ?? [:] {
            log += "\(key): \(value)\n"
        }
        if let body = data {
            let bodyString = NSString(data: body, encoding: String.Encoding.utf8.rawValue) ?? "Not utf8!";
            log += "\n\(bodyString)\n"
        }
        if let error = error {
            log += "\nError: \(error.localizedDescription)\n"
        }
        log += "------------------------\n";
        return log
    }

    private func parseErrResponse(_ response: [String: Any]) -> [Int]? {
        var messageParseError = false
        var rejectedSamples: [Int] = []

        func parseErrorDict(_ errDict: Any) {
            guard let errDict = errDict as? [String: Any] else {
                NSLog("Error message source field is not valid!")
                messageParseError = true
                return
            }
            guard let errStr = errDict["pointer"] as? String else {
                NSLog("Error message source pointer missing or invalid!")
                messageParseError = true
                return
            }
            print("next error is \(errStr)")
            guard errStr.count >= 2 else {
                NSLog("Error message pointer string too short!")
                messageParseError = true
                return
            }
            let parser = Scanner(string: errStr)
            parser.scanLocation = 1
            var index: Int = -1
            guard parser.scanInt(&index) else {
                NSLog("Unable to find index in error message!")
                messageParseError = true
                return
            }
            print("index of next bad sample is: \(index)")
            rejectedSamples.append(index)
        }

        if let errorArray = response["errors"] as? [[String: Any]] {
            for errorDict in errorArray {
                if let source = errorDict["source"] {
                    parseErrorDict(source)
                }
            }
        } else {
            if let source = response["source"] as? [String: Any] {
                parseErrorDict(source)
            }
        }

        if !messageParseError && rejectedSamples.count > 0 {
            return rejectedSamples
        } else {
            return nil
        }
    }

    // Retain last upload response data for error message debugging...
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        DDLogVerbose("mode: \(mode.rawValue)")
        lastData = data
    }
    var lastData: Data?

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        DDLogVerbose("mode: \(mode.rawValue)")

        DispatchQueue.main.async {
            DDLogInfo("Upload session became invalid. Mode: \(self.mode)")
            self.uploadSession = nil
            self.ensureUploadSession()
        }
    }

    // MARK: Private

    private func ensureUploadSession() {
        DDLogVerbose("mode: \(mode.rawValue)")
      
        guard self.uploadSession == nil else {
            return
        }

        if mode == .Current {
            // TODO: background upload - when in background, use background session (file based?), and when in foreground, use foreground session
            let configuration = URLSessionConfiguration.background(withIdentifier: "\(prefixedLocalId(self.backgroundUploadSessionIdentifier))-\(uniqueSessionId())")
            // TODO: background uploader - review timeouts for background session, it will be harder to use the variable timeouts on retry with background session requests
            // TODO: background uploader -  reconsider session for .Current .. when in foreground, ensure upload session just like historical .. when in background, use background session (or is it possible to use background task with normal session?
            
            configuration.timeoutIntervalForResource = 60
            configuration.timeoutIntervalForRequest = 60
            let newUploadSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            newUploadSession.delegateQueue.maxConcurrentOperationCount = 1 // So we can serialize the metadata and samples upload POSTs
            self.uploadSession = newUploadSession
        } else {
            let configuration = URLSessionConfiguration.default
            let newUploadSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.uploadSession = newUploadSession
        }

        DDLogInfo("Created upload session. Mode: \(self.mode)")
    }

    private func createPostBodyForBatchSamplesDelete(_ samplesToDeleteDictArray: [[String: AnyObject]]) throws -> (URL?, Data?) {
        DDLogVerbose("mode: \(mode.rawValue)")

        // Prepare upload delete body
        var validatedSamples = [[String: AnyObject]]()
        // Prevent serialization exceptions!
        for sample in samplesToDeleteDictArray {
            if JSONSerialization.isValidJSONObject(sample) {
                validatedSamples.append(sample)
            } else {
                DDLogError("Sample cannot be serialized to JSON!")
                DDLogError("Sample: \(sample)")
            }
        }
        if validatedSamples.isEmpty {
            return (nil, nil)
        }
        DDLogVerbose("Count of samples to delete: \(validatedSamples.count)")
        //DDLogInfo("Next samples to delete: \(validatedSamples)")
        return try self.serializePostBody(samples: validatedSamples, identifier: prefixedKey(prefix: self.mode.rawValue, type: "All", key: "deleteBatchSamples.data"))
    }

    func prefixedKey(prefix: String, type: String, key: String) -> String {
        let result = "\(prefix)-\(type)\(key)"
        //print("prefixedKey: \(result)")
        return result
    }

    private func createPostBodyForBatchSamplesUpload(_ samplesToUploadDictArray: [[String: AnyObject]]) throws -> (URL?, Data?) {
        DDLogVerbose("mode: \(mode.rawValue)")

        // Note: exceptions during serialization are NSException type, and won't get caught by a Swift do/catch, so pre-validate!
        return try self.serializePostBody(samples: samplesToUploadDictArray, identifier: prefixedKey(prefix: self.mode.rawValue, type: "All", key: "uploadBatchSamples.data"))
    }

    private func serializePostBody(samples: [[String: AnyObject]], identifier: String) throws -> (URL?, Data?) {
        DDLogVerbose("identifier: \(identifier)")

        let postBody = try JSONSerialization.data(withJSONObject: samples)
        // print("Post body for upload: \(postBody)")
      
        // If session is background session (with identifier), then write the post body to file
        if self.uploadSession?.configuration.identifier != nil {
            let postBodyUrl = getUploadURLForIdentifier(with: identifier)
            try postBody.write(to: postBodyUrl, options: .atomic)
            return (postBodyUrl, postBody)
        } else {
            return (nil, postBody)
        }
    }

    private func getUploadURLForIdentifier(with identifier: String) -> URL {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let postBodyUrl = cachesDirectory.appendingPathComponent(identifier)
        return postBodyUrl
    }

    private func setPendingUploadsState(uploadTaskIsPending: Bool) {
        let setting = mode == .Current ? settings.hasPendingCurrentUploads : settings.hasPendingHistoricalUploads
        setting.value = uploadTaskIsPending
    }

    private var uploadSession: URLSession?

    // use the following with prefixedLocalId to create ids unique to mode...
    private let backgroundUploadSessionIdentifier = "UploadSessionId"
    private let uploadSamplesTaskDescription = "Upload samples"
    private let deleteSamplesTaskDescription = "Delete samples"

    private func prefixedLocalId(_ key: String) -> String {
        return "\(self.mode.rawValue)-\(key)"
    }

    private func uniqueSessionId() -> String {
        // Get a persistent unique sequence number to use for session identifiers so we don't reuse identifiers
        // across invocations of the app, which could cause us to reattach to a session that the system cancelled
        // due to user force quitting the app or other reaosns. This would cause an immediate upload failure right
        // after starting an upload. (Although upload attempts with the same identifier _should_ succeed.)
        var uniqueSessionId: String = UserDefaults.standard.string(forKey: "UniqueUploadSessionId") ?? "0"
        let uniqueSesssionIdUInt64: UInt64 = (UInt64(uniqueSessionId) ?? 0) + 1
        uniqueSessionId = String(uniqueSesssionIdUInt64)
        UserDefaults.standard.set(uniqueSessionId, forKey: "UniqueUploadSessionId")
        DDLogVerbose("Created unique upload session id: " + uniqueSessionId);
        return uniqueSessionId
    }
}
