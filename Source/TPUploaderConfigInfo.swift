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

/// Configuration protocol for the TPHealthKitUploader framework.
///
/// The host app implements this to provide connectivity checks, user info, and callbacks.
/// Authentication and API calls are now handled by the injected TAPI instance (TidepoolKit).
public protocol TPUploaderConfigInfo {
    func isConnectedToNetwork() -> Bool

    /// current logged in user id
    func currentUserId() -> String?

    /// account for current user is a DSA
    func isDSAUser() -> Bool

    var currentUserName: String? { get }

    /// biological sex is gleaned from HealthKit, and uploaded when missing in the service.
    var bioSex: String? { get set }

    /// interface callbacks
    func onTurningOnInterface()
    func onTurnOnInterface()
    func onTurnOffInterface(_ error: Error?)

    /// uploader limits and timeout
    func samplesUploadLimits() -> [Int]
    func deletesUploadLimits() -> [Int]
    func uploaderTimeouts() -> [Int]

    /// suppress deletes, will NOT upload deletes if true
    func supressUploadDeletes() -> Bool

    /// simulate upload, will NOT upload if false
    func simulateUpload() -> Bool

    /// simulate upload, will NOT include sensitive info if false
    func includeSensitiveInfo() -> Bool

    /// logging callbacks
    func logVerbose(_ str: String)
    func logError(_ str: String)
    func logInfo(_ str: String)
    func logDebug(_ str: String)
}
