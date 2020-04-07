/*
* Copyright (c) 2015, Tidepool Project
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
import Alamofire
import SwiftyJSON
import CocoaLumberjack


/// APIConnector is a singleton object with the main responsibility of communicating to the Tidepool service:
/// - Given a username and password, login.
/// - Can refresh connection.
/// - Provides online/offline status.
class APIConnector {
    
    static var _connector: APIConnector?
    /// Supports a singleton for the application.
    class func connector() -> APIConnector {
        if _connector == nil {
        _connector = APIConnector()
        }
        return _connector!
    }
    
    // MARK: - Constants
    
    fileprivate let kCurrentServiceDefaultKey = "SCurrentService"
    fileprivate let kSessionTokenHeaderId = "X-Tidepool-Session-Token"
    fileprivate let kSessionTokenResponseId = "x-tidepool-session-token"

    // Error domain and codes
    fileprivate let kTidepoolMobileErrorDomain = "TidepoolMobileErrorDomain"
    fileprivate let kNoSessionTokenErrorCode = -1
    
    // Session token, acquired on login and saved in NSUserDefaults
    fileprivate let kSessionTokenDefaultKey = "SToken"
    fileprivate var _sessionToken: String?
    var sessionToken: String? {
        set(newToken) {
            if ( newToken != nil ) {
                UserDefaults.standard.setValue(newToken, forKey:kSessionTokenDefaultKey)
            } else {
                UserDefaults.standard.removeObject(forKey: kSessionTokenDefaultKey)
            }
            _sessionToken = newToken
        }
        get {
            return _sessionToken
        }
    }
    
    private let kLoggedInUserIDDefaultKey = "LoggedInUserId"
    private var _loggedInUserId: String?
    var loggedInUserId: String? {
        set(newLoggedInUserId) {
            if ( newLoggedInUserId != nil ) {
                UserDefaults.standard.setValue(newLoggedInUserId, forKey:kLoggedInUserIDDefaultKey)
            } else {
                UserDefaults.standard.removeObject(forKey: kLoggedInUserIDDefaultKey)
            }
            _loggedInUserId = newLoggedInUserId
        }
        get {
            return _loggedInUserId
        }
    }

    private let kLoggedInUserNameDefaultKey = "LoggedInUserName"
    private var _loggedInUserName: String?
    var loggedInUserName: String? {
        set(newLoggedInUserName) {
            if ( newLoggedInUserName != nil ) {
                UserDefaults.standard.setValue(newLoggedInUserName, forKey:kLoggedInUserNameDefaultKey)
            } else {
                UserDefaults.standard.removeObject(forKey: kLoggedInUserNameDefaultKey)
            }
            _loggedInUserName = newLoggedInUserName
        }
        get {
            return _loggedInUserName
        }
    }

    // Dictionary of servers and their base URLs
    let kServers = [
        "Development" :  "https://qa1.development.tidepool.org",
        "Staging" :      "https://qa2.development.tidepool.org",
        "Production" :   "https://api.tidepool.org"
    ]
    let kSortedServerNames = [
        "Development",
        "Staging",
        "Production"
    ]
    fileprivate let kDefaultServerName = "Staging"

    fileprivate var _currentService: String?
    var currentService: String? {
        set(newService) {
            if newService == nil {
                UserDefaults.standard.removeObject(forKey: kCurrentServiceDefaultKey)
                _currentService = nil
            } else {
                if kServers[newService!] != nil {
                    UserDefaults.standard.setValue(newService, forKey: kCurrentServiceDefaultKey)
                    _currentService = newService
                }
            }
        }
        get {
            if _currentService == nil {
                if let service = UserDefaults.standard.string(forKey: kCurrentServiceDefaultKey) {
                    // don't set a service this build does not support
                    if kServers[service] != nil {
                        _currentService = service
                    }
                }
            }
            if _currentService == nil || kServers[_currentService!] == nil {
                _currentService = kDefaultServerName
            }
            return _currentService
        }
    }
    
    // Base URL for API calls, set during initialization
    var baseUrl: URL?
    var baseUrlString: String?
    
    // Reachability object, valid during lifetime of this APIConnector, and convenience function that uses this
    // Register for ReachabilityChangedNotification to monitor reachability changes             
    var reachability: Reachability?
    func isConnectedToNetwork() -> Bool {
        if let reachability = reachability {
            return reachability.isReachable
        } else {
            DDLogError("Reachability object not configured!")
            return true
        }
    }

    func serviceAvailable() -> Bool {
        if !isConnectedToNetwork() || sessionToken == nil {
            return false
        }
        return true
    }

    // MARK: Initialization
    
    /// Creator of APIConnector must call this function after init!
    func configure() -> APIConnector {
        self.baseUrlString = kServers[currentService!]!
        self.baseUrl = URL(string: baseUrlString!)!
        DDLogInfo("Using service: \(String(describing: self.baseUrl))")
        self.sessionToken = UserDefaults.standard.string(forKey: kSessionTokenDefaultKey)
        self.loggedInUserId = UserDefaults.standard.string(forKey: kLoggedInUserIDDefaultKey)
        self.loggedInUserName = UserDefaults.standard.string(forKey: kLoggedInUserNameDefaultKey)
        if let reachability = reachability {
            reachability.stopNotifier()
        }
        self.reachability = Reachability()
        
        do {
           try reachability?.startNotifier()
        } catch {
            DDLogError("Unable to start notifier!")
        }
        return self
    }
    
    deinit {
        reachability?.stopNotifier()
    }
    
    func switchToServer(_ serverName: String) {
        if (currentService != serverName) {
            currentService = serverName
            // refresh connector since there is a new service...
            _ = configure()
            DDLogInfo("Switched to \(serverName) server")
            
            let notification = Notification(name: Notification.Name(rawValue: "switchedToNewServer"), object: nil)
            NotificationCenter.default.post(notification)
        }
    }
    
    /// Logs in the user and obtains the session token for the session (stored internally)
    func login(_ username: String, password: String, completion: @escaping (Result<[String: Any?]>, Int?) -> (Void)) {
        // force sessionToken nil if not already nil!
        self.sessionToken = nil
        // Similar to email inputs in HTML5, trim the email (username) string of whitespace
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Set our endpoint for login
        let endpoint = "auth/login"
        
        // Create the authorization string (user:pass base-64 encoded)
        let base64LoginString = NSString(format: "%@:%@", trimmedUsername, password)
            .data(using: String.Encoding.utf8.rawValue)?
            .base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))
        
        // Set our headers with the login string
        let headers = ["Authorization" : "Basic " + base64LoginString!]
        
        // Send the request and deal with the response as JSON
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        sendRequest(.post, endpoint: endpoint, headers:headers).responseJSON { response in
            UIApplication.shared.isNetworkActivityIndicatorVisible = false
            if ( response.result.isSuccess ) {
                // Look for the auth token
                self.sessionToken = response.response!.allHeaderFields[self.kSessionTokenResponseId] as! String?
                DDLogInfo("Login returned token: \(self.sessionToken!)")

                if let jsonDict = response.result.value as? [String: Any?] {
                    self.loggedInUserId = jsonDict["userid"] as? String
                    self.loggedInUserName = jsonDict["username"] as? String
                    if self.loggedInUserId != nil {
                        DDLogInfo("Login success!")
                        completion(Result.success(jsonDict), nil)
                    } else {
                        completion(Result.failure(NSError(domain: self.kTidepoolMobileErrorDomain,
                                                          code: -1,
                                                          userInfo: ["description":"Login json did not contain userid!", "result":response.result.value!])), -1)
                    }
                } else {
                    DDLogError("ERR: Unable to parse login result!")
                    completion(Result.success([:]), nil)
                }
            } else {
                let statusCode = response.response?.statusCode
                completion(Result.failure(response.result.error!), statusCode)
            }
        }
    }
 
    func logout() {
        // Clear our session token and remove entries from the db
        self.sessionToken = nil
        self.loggedInUserId = nil
        self.loggedInUserName = nil
    }

    // MARK: - Internal methods
    
    // User-agent string, based on that from Alamofire, but common regardless of whether Alamofire library is used
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

    private func sessionManager() -> SessionManager {
        if _sessionManager == nil {
            // get the default headers
            var alamoHeaders = Alamofire.SessionManager.defaultHTTPHeaders
            // add our custom user-agent
            alamoHeaders["User-Agent"] = self.userAgentString()
            // create a custom session configuration
            let configuration = URLSessionConfiguration.default
            // add the headers
            configuration.httpAdditionalHeaders = alamoHeaders
            // create a session manager with the configuration
            _sessionManager = Alamofire.SessionManager(configuration: configuration)
        }
        return _sessionManager!
    }
    private var _sessionManager: SessionManager?
    
    // Sends a request to the specified endpoint
    private func sendRequest(_ requestType: HTTPMethod? = .get,
        endpoint: (String),
        parameters: [String: AnyObject]? = nil,
        headers: [String: String]? = nil) -> (DataRequest)
    {
        let url = baseUrl!.appendingPathComponent(endpoint)
        
        // Get our API headers (the session token) and add any headers supplied by the caller
        var apiHeaders = getApiHeaders()
        if ( apiHeaders != nil ) {
            if ( headers != nil ) {
                for(k, v) in headers! {
                    _ = apiHeaders?.updateValue(v, forKey: k)
                }
            }
        } else {
            // We have no headers of our own to use- just use the caller's directly
            apiHeaders = headers
        }
        
        // Fire off the network request
        DDLogInfo("sendRequest url: \(url), params: \(parameters ?? [:]), headers: \(apiHeaders ?? [:])")
        return self.sessionManager().request(url, method: requestType!, parameters: parameters, headers: apiHeaders).validate()
        //debugPrint(result)
        //return result
    }
    
    func getApiHeaders() -> [String: String]? {
        if ( sessionToken != nil ) {
            return [kSessionTokenHeaderId : sessionToken!]
        }
        return nil
    }
    
 }
