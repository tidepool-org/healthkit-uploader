/*
 * Copyright (c) 2019-2025, Tidepool Project
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
import HealthKit
import TidepoolKit

/// Main entry point for the HealthKit uploader framework.
///
/// Refactored to accept a TidepoolKit `TAPI` instance for all server communication,
/// replacing the legacy `ServiceAPI` / session token approach.
public class TPUploader {

    /// Nil if not configured yet
    static var sharedInstance: TPUploader?

    //
    // MARK: - public enums and constants
    //

    public static let ErrorDomain = "TPUploader"

    public enum ErrorCodes: Int {
        case noHealthKit = -1
        case noBaseUrl = -2
        case noSession = -3
        case noSessionToken = -4
        case noUploadId = -5
        case noUploadUrl = -6
        case noBody = -7
        case noUser = -8
        case noDSAUser = -9
        case noNetwork = -101
        case noProtectedHealthKitData = -102
        case unknownError = -999
    }

    public enum Mode: String {
        case Current = "Current"
        case HistoricalAll = "HistoricalAll"
    }

    public enum StoppedReason {
        case error(error: Error)
        case interfaceTurnedOff
        case uploadingComplete
    }

    /// The TidepoolKit API instance used for all server communication.
    /// Replaces the legacy ServiceAPI (session tokens, manual URL construction).
    public let api: TAPI

    private let config: TPUploaderConfigInfo
    private let service: TPUploaderServiceAPIBridge
    private let tzTracker: TPTimeZoneTracker
    private let settings = HKGlobalSettings.sharedInstance

    let hkUploadMgr: HealthKitUploadManager
    let hkMgr: HealthKitManager
    let hkConfig: HealthKitConfiguration

    /// Initialize the uploader with a TidepoolKit TAPI instance and configuration.
    ///
    /// - Parameters:
    ///   - api: The TidepoolKit API actor. Handles auth, tokens, and all API endpoints.
    ///   - config: Configuration protocol providing connectivity checks, user info, and callbacks.
    public init(api: TAPI, config: TPUploaderConfigInfo) {
        debugConfig = config // special copy to get debug output during init!
        DDLogInfo("TPUploader init - version \(TPUploaderServiceAPIBridge.frameworkVersion)")
        self.api = api
        self.config = config
        self.service = TPUploaderServiceAPIBridge(api: api, config: config)
        self.tzTracker = TPTimeZoneTracker()
        self.hkConfig = HealthKitConfiguration(config, healthKitUploadTypes: [
            HealthKitUploadTypeBloodGlucose(),
            HealthKitUploadTypeCarb(),
            HealthKitUploadTypeInsulin(),
            HealthKitUploadTypeWorkout(),
        ])
        self.hkUploadMgr = HealthKitUploadManager.sharedInstance
        self.hkMgr = HealthKitManager.sharedInstance
        TPUploader.sharedInstance = self
    }

    //
    // MARK: - public methods
    //

    public func configure() {
        hkConfig.configureHealthKitInterface()
    }

    public func isInterfaceOn() -> Bool {
        return hkConfig.isInterfaceOn
    }

    public func isTurningInterfaceOn() -> Bool {
        return hkConfig.turningOnHKInterface
    }

    public func shouldShowHealthKitUI() -> Bool {
        return hkMgr.isHealthDataAvailable && config.isDSAUser()
    }

    public func isHealthKitAuthorized() -> Bool {
        return hkMgr.isHealthKitAuthorized
    }

    public func disableHealthKitInterface() {
        DDLogInfo("\(#function)")
        hkConfig.disableHealthKitInterface()
        // clear uploadId to be safe... also for logout.
        TPUploaderServiceAPIBridge.connector?.currentUploadId = nil
    }

    public func enableHealthKitInterfaceAndAuthorize(completion: ((Bool) -> Void)? = nil) {
        hkConfig.enableHealthKitInterfaceAndAuthorize(completion: completion)
    }

    public func isHealthKitInterfaceEnabledForCurrentUser() -> Bool {
        return hkConfig.isHealthKitInterfaceEnabledForCurrentUser()
    }

    public func isHealthKitInterfaceConfiguredForOtherUser() -> Bool {
        return hkConfig.isHealthKitInterfaceConfiguredForOtherUser()
    }

    public func curHKUserName() -> String? {
        return hkConfig.healthKitUserTidepoolUsername()
    }

    public func currentUploadStats() -> [TPUploaderStats] {
        return hkUploadMgr.statsForMode(TPUploader.Mode.Current)
    }

    public func uploaderProgress() -> TPUploaderGlobalStats {
        return settings.currentProgress()
    }

    public func historicalUploadStats() -> [TPUploaderStats] {
        return hkUploadMgr.statsForMode(TPUploader.Mode.HistoricalAll)
    }

    public func isUploadInProgressForMode(_ mode: TPUploader.Mode) -> Bool {
        return hkUploadMgr.isUploadInProgressForMode(mode)
    }

    public func retryInfoForMode(_ mode: TPUploader.Mode) -> (Int, Int) {
        return hkUploadMgr.retryInfoForMode(mode)
    }

    public func startUploading(_ mode: TPUploader.Mode) {
        if config.currentUserId() != nil {
            hkUploadMgr.startUploading(mode: mode, config: config)
        } else {
            DDLogVerbose("ERR: startUploading ignored, no current user!")
        }
    }

    public func stopUploading(mode: TPUploader.Mode, reason: TPUploader.StoppedReason) {
        hkUploadMgr.stopUploading(mode: mode, reason: reason)
    }

    public func stopUploading(reason: TPUploader.StoppedReason) {
        hkUploadMgr.stopUploading(reason: reason)
    }

    public func resumeUploadingIfResumable() {
        if config.currentUserId() != nil {
            hkUploadMgr.resumeUploadingIfResumable(config: config)
        } else {
            DDLogVerbose("ERR: resumeUploadingIfResumable ignored, no current user!")
        }
    }

    public func resetPersistentStateForMode(_ mode: TPUploader.Mode) {
        hkUploadMgr.resetPersistentStateForMode(mode)
    }

    public var hasPresentedSyncUI: Bool {
        get { settings.hasPresentedSyncUI.value }
        set { settings.hasPresentedSyncUI.value = newValue }
    }
}


// MARK: - TPUploaderServiceAPIBridge

/// Bridge class that replaces the legacy `TPUploaderServiceAPI` / `ServiceAPI.swift`.
/// Uses TidepoolKit's TAPI actor for dataset management (configureUploadId),
/// while caching accessToken + environment via TAPIObserver for synchronous
/// request construction (makeDataUploadRequest, postTimezoneChangesEvent).
class TPUploaderServiceAPIBridge: NSObject, TAPIObserver {

    static var connector: TPUploaderServiceAPIBridge?

    /// Framework version read from the bundle's CFBundleShortVersionString.
    static let frameworkVersion: String = {
        return Bundle(for: TPUploader.self).infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
    }()

    private let api: TAPI
    // `var` (not `let`) so the settable `bioSex` property can be written back through the
    // (non-class-bound) config existential during the biological-sex backfill.
    private var config: TPUploaderConfigInfo
    private let defaults = UserDefaults.standard
    private let HKDataUploadIdKey = "kHKDataUploadIdKey"
    private let kSessionTokenHeaderId = "X-Tidepool-Session-Token"

    /// Serializes access to the cached session state and upload id. These are written from
    /// the TAPIObserver callback (main queue) and the init seeding Task (cooperative executor),
    /// and read during request construction. The lock makes those accesses safe regardless of
    /// which queue the caller runs on.
    private let cacheLock = NSLock()

    /// Cached from TAPIObserver — read as an atomic snapshot via `cachedSession()`.
    private var _cachedAccessToken: String?
    /// Cached from TAPIObserver — read as an atomic snapshot via `cachedSession()`.
    private var _cachedEnvironment: TEnvironment?

    var currentUploadId: String? {
        get {
            cacheLock.lock()
            defer { cacheLock.unlock() }
            if _currentUploadId == nil {
                _currentUploadId = defaults.string(forKey: HKDataUploadIdKey)
            }
            return _currentUploadId
        }
        set {
            cacheLock.lock()
            defer { cacheLock.unlock() }
            defaults.setValue(newValue, forKey: HKDataUploadIdKey)
            _currentUploadId = newValue
        }
    }
    private var _currentUploadId: String?

    /// Atomic snapshot of the cached access token + environment, so request construction never
    /// pairs a token from one session with the environment of another. Returns nil until the
    /// session has been observed/seeded.
    private func cachedSession() -> (token: String, environment: TEnvironment)? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let token = _cachedAccessToken, let environment = _cachedEnvironment else {
            return nil
        }
        return (token, environment)
    }

    init(api: TAPI, config: TPUploaderConfigInfo) {
        self.api = api
        self.config = config
        super.init()
        TPUploaderServiceAPIBridge.connector = self

        // Observe TAPI session changes to cache token/environment. The observer fires on the
        // main queue; only future changes are delivered, so seed the current session here too.
        Task {
            await api.addObserver(self, queue: .main)
            let session = await api.session
            cacheLock.lock()
            _cachedAccessToken = session?.accessToken
            _cachedEnvironment = session?.environment
            cacheLock.unlock()
        }
    }

    // MARK: - TAPIObserver

    func apiDidUpdateSession(_ session: TSession?) {
        // Called on main queue (specified in addObserver). Update token + environment together
        // under the lock so readers see a consistent pair.
        cacheLock.lock()
        _cachedAccessToken = session?.accessToken
        _cachedEnvironment = session?.environment
        cacheLock.unlock()
        DDLogInfo("TPUploaderServiceAPIBridge: session updated, token \(session != nil ? "present" : "nil")")
    }

    // MARK: - Network helpers

    func isConnectedToNetwork() -> Bool {
        return config.isConnectedToNetwork()
    }

    /// Configure the upload dataset ID using TidepoolKit.
    /// Replaces legacy fetchDataset/createDataset methods that used manual URL construction + session tokens.
    func configureUploadId() async throws {
        guard config.currentUserId() != nil else {
            throw NSError(domain: TPUploader.ErrorDomain, code: TPUploader.ErrorCodes.noUser.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "Not logged in"])
        }

        guard config.isDSAUser() else {
            throw NSError(domain: TPUploader.ErrorDomain, code: TPUploader.ErrorCodes.noDSAUser.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "Not a DSA user"])
        }

        if currentUploadId != nil { return }

        DDLogInfo("configureUploadId: fetching existing dataset")

        // Try to fetch existing dataset via TidepoolKit
        let filter = TDataSet.Filter(clientName: "org.tidepool.mobile")
        let dataSets = try await api.listDataSets(filter: filter)

        if let existingDataSet = dataSets.first {
            DDLogInfo("Dataset fetched existing: \(existingDataSet.uploadId ?? "nil")")
            currentUploadId = existingDataSet.uploadId
            return
        }

        // No existing dataset — create one via TidepoolKit
        DDLogInfo("No upload id exists, try creating new dataset!")
        let newDataSet = TDataSet(
            dataSetType: .continuous,
            client: TDataSet.Client(name: "org.tidepool.mobile", version: TPUploaderServiceAPIBridge.frameworkVersion),
            deduplicator: TDataSet.Deduplicator(name: .dataSetDeleteOrigin)
        )
        let createdDataSet = try await api.createDataSet(newDataSet)
        DDLogInfo("New dataset created: \(createdDataSet.uploadId ?? "nil")")
        currentUploadId = createdDataSet.uploadId
    }

    // MARK: - Synchronous request construction (for URLSession upload tasks)

    /// Construct a URLRequest for data upload/delete using cached token and environment.
    /// Called synchronously from URLSession delegates — cannot use `await` here.
    func makeDataUploadRequest(_ httpMethod: String) throws -> URLRequest {
        DDLogVerbose("\(#function)")

        guard config.isConnectedToNetwork() else {
            throw NSError(domain: TPUploader.ErrorDomain, code: TPUploader.ErrorCodes.noNetwork.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "Unable to upload. The Internet connection appears to be offline."])
        }

        guard let uploadId = currentUploadId else {
            throw NSError(domain: TPUploader.ErrorDomain, code: TPUploader.ErrorCodes.noUploadId.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "Unable to upload. No upload id is available."])
        }

        guard let (token, environment) = cachedSession() else {
            throw NSError(domain: TPUploader.ErrorDomain, code: TPUploader.ErrorCodes.noSessionToken.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "Unable to upload. No session token or API environment available."])
        }

        let path = "/v1/data_sets/\(uploadId)/data"
        let url = try environment.url(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: kSessionTokenHeaderId)
        request.setValue(self.userAgentString(), forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Post timezone change events using cached token/environment.
    /// Fires a URLSession POST (completion-based) for backward compatibility.
    func postTimezoneChangesEvent(_ tzChanges: [(time: String, newTzId: String, oldTzId: String?)], _ completion: @escaping (String?) -> (Void)) {
        guard let currentUploadId = self.currentUploadId else {
            DDLogInfo("Timezone change upload fail: no upload id!")
            completion(nil)
            return
        }

        guard let (token, environment) = cachedSession() else {
            DDLogInfo("Timezone change upload fail: no session!")
            completion(nil)
            return
        }

        var changesToUploadDictArray = [[String: AnyObject]]()
        var lastTzUploaded: String?
        for tzChange in tzChanges {
            var sampleToUploadDict = [String: AnyObject]()
            sampleToUploadDict["time"] = tzChange.time as AnyObject
            sampleToUploadDict["type"] = "deviceEvent" as AnyObject
            sampleToUploadDict["subType"] = "timeChange" as AnyObject
            let toDict = ["timeZoneName": tzChange.newTzId]
            lastTzUploaded = tzChange.newTzId
            sampleToUploadDict["to"] = toDict as AnyObject
            if let oldTzId = tzChange.oldTzId {
                let fromDict = ["timeZoneName": oldTzId]
                sampleToUploadDict["from"] = fromDict as AnyObject
            }
            changesToUploadDictArray.append(sampleToUploadDict)
        }

        let body: Data?
        do {
            body = try JSONSerialization.data(withJSONObject: changesToUploadDictArray, options: [])
            if let postBodyJson = String(data: body!, encoding: .utf8) {
                DDLogInfo("Posting json for timechange: \(postBodyJson)")
            }
        } catch {
            DDLogError("Failed to create body!")
            completion(nil)
            return
        }

        let path = "/v1/data_sets/\(currentUploadId)/data"
        guard let url = try? environment.url(path: path) else {
            DDLogError("Failed to construct URL for timezone event!")
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: kSessionTokenHeaderId)
        request.setValue(self.userAgentString(), forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        let task = URLSession.shared.dataTask(with: request) { (_, response, error) in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                    DDLogInfo("Timezone change upload succeeded!")
                    completion(lastTzUploaded)
                } else {
                    DDLogInfo("Timezone change upload failed!")
                    completion(nil)
                }
            }
        }
        task.resume()
    }

    // MARK: - Profile biological sex backfill

    /// Fill in the Tidepool patient's biological sex if it is missing and we can read it from HealthKit.
    ///
    /// Mirrors the legacy behavior: reads biological sex from HealthKit, then (if not already cached on
    /// the config) fetches the raw profile, and — only when the patient record is present and has no
    /// usable biologicalSex — merges the value in (preserving all other profile fields) and POSTs it back.
    func updateProfileBioSexCheck() {
        DDLogInfo("\(#function)")

        // Already have it (or already backfilled this session) — nothing to do.
        guard config.bioSex == nil else { return }

        guard let healthStore = HealthKitManager.sharedInstance.healthStore else {
            DDLogInfo("No HealthKit store available for bio-sex check")
            return
        }

        let bioSexString: String
        do {
            let sex = try healthStore.biologicalSex()
            guard sex.biologicalSex != .notSet else {
                DDLogInfo("biological sex not set in HK!")
                return
            }
            bioSexString = sex.biologicalSex.stringRepresentation
        } catch {
            DDLogInfo("throw from call for biologicalSex: not authorized?")
            return
        }

        guard let userId = config.currentUserId() else { return }
        DDLogInfo("biologicalSex is \(bioSexString)")

        updateProfile(userId, biologicalSex: bioSexString) { [weak self] updateOk in
            DDLogInfo("Result of profile update: \(updateOk)")
            // Cache only on success so a transient failure can be retried next time.
            if updateOk {
                self?.config.bioSex = bioSexString
            }
        }
    }

    /// Fetches the raw profile JSON, and if the patient record exists and has no usable biologicalSex,
    /// merges in `biologicalSex` (preserving every other field) and POSTs the merged profile back.
    private func updateProfile(_ userId: String, biologicalSex: String, _ completion: @escaping (Bool) -> Void) {
        guard let (token, environment) = cachedSession() else {
            DDLogError("No session for profile update!")
            completion(false)
            return
        }

        let path = "/metadata/\(userId)/profile"
        guard let url = try? environment.url(path: path) else {
            DDLogError("Failed to construct URL for profile update!")
            completion(false)
            return
        }

        var getRequest = URLRequest(url: url)
        getRequest.httpMethod = "GET"
        getRequest.setValue(token, forHTTPHeaderField: kSessionTokenHeaderId)
        getRequest.setValue(self.userAgentString(), forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: getRequest) { [weak self] data, _, error in
            guard let self = self else { completion(false); return }

            guard error == nil, let data = data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                DDLogError("Failed to fetch profile for bio-sex update!")
                completion(false)
                return
            }

            guard var patient = json["patient"] as? [String: Any] else {
                DDLogInfo("No patient record in the fetched profile, not a DSA user!")
                completion(false)
                return
            }

            if let currentBioSex = patient["biologicalSex"] as? String, currentBioSex.lowercased() != "unknown" {
                DDLogInfo("biological sex '\(currentBioSex)' already set in Tidepool, should not update!")
                completion(false)
                return
            }

            patient["biologicalSex"] = biologicalSex
            var merged = json
            merged["patient"] = patient

            guard let body = try? JSONSerialization.data(withJSONObject: merged, options: []) else {
                DDLogError("Serialization error merging bio-sex into profile!")
                completion(false)
                return
            }

            var postRequest = URLRequest(url: url)
            postRequest.httpMethod = "POST"
            postRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            postRequest.setValue(token, forHTTPHeaderField: self.kSessionTokenHeaderId)
            postRequest.setValue(self.userAgentString(), forHTTPHeaderField: "User-Agent")
            postRequest.httpBody = body

            URLSession.shared.dataTask(with: postRequest) { _, response, _ in
                let ok = (response as? HTTPURLResponse).map { $0.statusCode == 200 || $0.statusCode == 201 } ?? false
                if ok {
                    DDLogInfo("Posted updated profile successfully!")
                } else {
                    DDLogInfo("Post of updated profile failed!")
                }
                completion(ok)
            }.resume()
        }.resume()
    }

    // MARK: - User agent

    /// User-agent string, based on that from Alamofire, but common regardless of whether Alamofire library is used
    private func userAgentString() -> String {
        if _userAgentString == nil {
            _userAgentString = {
                if let info = Bundle.main.infoDictionary {
                    let executable = info[kCFBundleExecutableKey as String] as? String ?? "Unknown"
                    let bundle = info[kCFBundleIdentifierKey as String] as? String ?? "Unknown"
                    let appVersion = info["CFBundleShortVersionString"] as? String ?? "Unknown"
                    let appBuild = info[kCFBundleVersionKey as String] as? String ?? "Unknown"

                    let osNameVersion: String = {
                        let version = ProcessInfo.processInfo.operatingSystemVersion
                        let versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"

                        let osName: String = {
                            #if os(iOS)
                            return "iOS"
                            #elseif os(watchOS)
                            return "watchOS"
                            #elseif os(tvOS)
                            return "tvOS"
                            #elseif os(macOS)
                            return "OS X"
                            #elseif os(Linux)
                            return "Linux"
                            #else
                            return "Unknown"
                            #endif
                        }()

                        return "\(osName) \(versionString)"
                    }()

                    return "\(executable)/\(appVersion) (\(bundle); build:\(appBuild); \(osNameVersion))"
                }

                return "TidepoolMobile"
            }()
        }
        return _userAgentString!
    }
    private var _userAgentString: String?
}
