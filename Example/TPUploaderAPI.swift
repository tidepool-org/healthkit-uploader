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
import CocoaLumberjack
import TPHealthKitUploader

/// The singleton of this class, accessed and initialized via TPUploaderAPI.connector(), initializes the uploader interface and provides it with the necessary callback functions.
class TPUploaderAPI: TPUploaderConfigInfo {
    
    static var _connector: TPUploaderAPI?
    /// Supports a singleton for the application.
    class func connector() -> TPUploaderAPI {
        if _connector == nil {
            let connector = TPUploaderAPI.init()
            _connector = connector
            connector.configure()
        }
        return _connector!
    }

    /// Use this to call various framework api's
    var uploader: TPUploader!

    private init() {
        service = APIConnector.connector()
        // caller needs to call configure to intialize the uploader framework!
    }
    private func configure() {
        uploader = TPUploader(self)
    }

    private var service: APIConnector

    //
    // MARK: - TPUploaderConfigInfo protocol
    //
    
    //
    // Service API functions
    //
    func isConnectedToNetwork() -> Bool {
        let result = service.isConnectedToNetwork()
        DDLogInfo("\(#function) - TPUploaderConfigInfo protocol, returning: \(result)")
        return result
    }
    
    func sessionToken() -> String? {
        let result = service.sessionToken
        DDLogInfo("\(#function) - TPUploaderConfigInfo protocol, returning: \(result ?? "nil")")
        return result
    }
    
    func baseUrlString() -> String? {
        let result = service.baseUrlString
        DDLogInfo("\(#function) - TPUploaderConfigInfo protocol, returning: \(result ?? "nil")")
        return result
    }

    func currentUserId() -> String? {
        let result = service.loggedInUserId
        DDLogInfo("\(#function) - TPUploaderConfigInfo protocol, returning: \(result ?? "nil")")
        return result
    }
    
    var currentUserName: String? {
        get {
            let result = service.loggedInUserName
            DDLogInfo("\(#function) - TPUploaderConfigInfo protocol, returning: \(result ?? "nil")")
            return result
        }
    }

    func isDSAUser() -> Bool {
        let result = true
        DDLogInfo("\(#function) - TPUploaderConfigInfo protocol, returning: \(result)")
        return result
    }
    
    var bioSex: String? {
        get {
            return nil
        }
        set {
            return
        }
    }
    
    let uploadFrameWork: StaticString = "uploader"
    func logVerbose(_ str: String) {
        DDLogVerbose(str, file: uploadFrameWork, function: uploadFrameWork)
    }
    
    func logError(_ str: String) {
        DDLogError(str, file: uploadFrameWork, function: uploadFrameWork)
    }
    
    func logInfo(_ str: String) {
        DDLogInfo(str, file: uploadFrameWork, function: uploadFrameWork)
    }
    
    func logDebug(_ str: String) {
        DDLogDebug(str, file: uploadFrameWork, function: uploadFrameWork)
    }

}
