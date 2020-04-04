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
import HealthKit

public enum HKDataLogPhase : CaseIterable {
    case read
    case gather
    case upload
}

/// User of the TPHealthKitUploader framework must configure the framework passing an object with this protocol which the framework will use as documented below.
public protocol TPUploaderConfigInfo {
    func isConnectedToNetwork() -> Bool
    /// Nil when logged out
    func sessionToken() -> String?
    /// base string to constuct url for current service.
    func baseUrlString() -> String?
    /// current logged in user id
    func currentUserId() -> String?
    /// account for current user is a DSA
    func isDSAUser() -> Bool
    var currentUserName: String? { get }
    /// biological sex is gleaned from HealthKit, and uploaded when missing in the service.
    var bioSex: String? { get set }
  
    /// interface callbacks
    func onTurningOnInterface();
    func onTurnOnInterface();
    func onTurnOffInterface(_ error: Error?);
  
    /// uploader limits and timmeout (will retry up to n times, using the Int values in the array, the length of the array must be the same for these
    func samplesUploadLimits() -> [Int]
    func deletesUploadLimits() -> [Int]
    func uploaderTimeouts() -> [Int]
  
    /// suppress deletes, will NOT upload deletes if true
    func supressUploadDeletes() -> Bool
  
    /// simulate upload, will NOT upload if false
    func simulateUpload() -> Bool
  
    /// simulate upload, will NOT include sensitive info (like auth token, and curl request/response for testing, which conain auth token) if false
    func includeSensitiveInfo() -> Bool

    /// logging callbacks
    func logVerbose(_ str: String)
    func logError(_ str: String)
    func logInfo(_ str: String)
    func logDebug(_ str: String)
  
    /// health data logging callbacks

    func openDataLogs(mode: TPUploader.Mode, isFresh: Bool)
    func logData(mode: TPUploader.Mode, phase: HKDataLogPhase, isRetry: Bool, samples: [HKSample]?, deletes: [HKDeletedObject]?)
    func logData(mode: TPUploader.Mode, phase: HKDataLogPhase, isRetry: Bool, samples: [[String: AnyObject]]?, deletes: [[String: AnyObject]]?)
}

