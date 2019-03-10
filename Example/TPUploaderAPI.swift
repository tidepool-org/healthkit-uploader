//
//  TPUploaderAPI.swift
//  UploaderTester
//
//  Created by Larry Kenyon on 2/21/19.
//  Copyright © 2019 Tidepool. All rights reserved.
//

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
            connector.configure()
            _connector = connector
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
    // MARK: - TPUploader API
    //
    var enabledForCurrentUser: Bool {
        get {
            return false
        }
    }
    
    //
    // MARK: - TPUploaderConfigInfo protocol
    //
    
    //
    // Service API functions
    //
    func isConnectedToNetwork() -> Bool {
        DDLogInfo("\(#function) - TPUploaderConfigInfo protocol")
        return service.isConnectedToNetwork()
    }
    
    func sessionToken() -> String? {
        DDLogInfo("\(#function) - TPUploaderConfigInfo protocol")
        return service.sessionToken
    }
    
    func baseUrlString() -> String? {
        DDLogInfo("\(#function) - TPUploaderConfigInfo protocol")
        return service.baseUrlString
    }

    func trackMetric(_ metric: String) {
        DDLogInfo("\(#function) - TPUploaderConfigInfo protocol")
        // should report metric to metric tracking service
        // TODO: document any metrics tracked in uploader!
    }
    
    func currentUserId() -> String? {
        DDLogInfo("\(#function) - TPUploaderConfigInfo protocol")
        return service.loggedInUserId
    }
    
    var currentUserName: String? {
        get {
            DDLogInfo("\(#function) - TPUploaderConfigInfo protocol")
            return service.loggedInUserName
        }
    }

    func isDSAUser() -> Bool {
        DDLogInfo("\(#function) - TPUploaderConfigInfo protocol")
        return true
    }
    
    var bioSex: String? {
        get {
            return nil
        }
        set {
            return
        }
    }
    
    func logVerbose(_ str: String) {
        DDLogVerbose(str)
    }
    
    func logError(_ str: String) {
        DDLogError(str)
    }
    
    func logInfo(_ str: String) {
        DDLogInfo(str)
    }
    
    func logDebug(_ str: String) {
        DDLogDebug(str)
    }

}
