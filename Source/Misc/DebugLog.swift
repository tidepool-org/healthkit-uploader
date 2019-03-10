//
//  DebugLog.swift
//  TPHealthKitUploader
//
//  Created by Larry Kenyon on 3/6/19.
//  Copyright © 2019 Tidepool. All rights reserved.
//

import Foundation

/// Include these here to translate debug functions into protocol calls
func DDLogVerbose(_ str: String) { TPUploader.sharedInstance?.config.logVerbose(str) }
func DDLogInfo(_ str: String) { TPUploader.sharedInstance?.config.logInfo(str) }
func DDLogDebug(_ str: String) { TPUploader.sharedInstance?.config.logDebug(str) }
func DDLogError(_ str: String) { TPUploader.sharedInstance?.config.logError(str) }
