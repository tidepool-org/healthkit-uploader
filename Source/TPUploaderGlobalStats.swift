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

public struct TPUploaderGlobalStats {
    init(lastUpload: Date?, totalHistDays: Int, currentHistDay: Int, totalHistSamples: Int, totalHistDeletes: Int, totalCurSamples: Int, totalCurDeletes: Int, currentUploadEarliestSampleTime: Date?, currentUploadLatestSampleTime: Date?, currentStartDate: Date?, historicalUploadEarliestSampleTime: Date?, historicalUploadLatestSampleTime: Date?) {
        self.lastSuccessfulCurrentUploadTime = lastUpload
        self.currentDayHistorical = currentHistDay
        self.totalDaysHistorical = totalHistDays
        self.totalSamplesHistorical = totalHistSamples
        self.totalDeletesHistorical = totalHistDeletes
        self.historicalUploadEarliestSampleTime = historicalUploadEarliestSampleTime
        self.historicalUploadLatestSampleTime = historicalUploadLatestSampleTime
        self.totalSamplesCurrent = totalCurSamples
        self.totalDeletesCurrent = totalCurDeletes
        self.currentUploadEarliestSampleTime = currentUploadEarliestSampleTime
        self.currentUploadLatestSampleTime = currentUploadLatestSampleTime
        self.currentStartDate = currentStartDate
    }
    
    // Stats for uploading current samples:
    public var lastSuccessfulCurrentUploadTime: Date? = nil
    
    // Stats for uploading historical samples:
    /// The number of days between the earliest HK sample (across all types) and the historical/current date boundary (samples after the boundary are handled by the current anchor query).
    public var totalDaysHistorical = 0
    /// The number of days between the earliest HK sample uploaded in the historical upload and the historical/current date boundary.
    public var currentDayHistorical = 0
    /// The total number of historical samples uploaded across all types
    public var totalSamplesHistorical = 0
    /// The total number of historical deletes uploaded across all types
    public var totalDeletesHistorical = 0
    /// The earliest sample time for historical samples across all types
    public var historicalUploadEarliestSampleTime: Date? = nil
    /// The latest sample time for historical samples across all types
    public var historicalUploadLatestSampleTime: Date? = nil
    /// The total number of current samples uploaded across all types
    public var totalSamplesCurrent = 0
    /// The total number of current deletes uploaded across all types
    public var totalDeletesCurrent = 0
    /// The earliest sample time for current samples across all types
    public var currentUploadEarliestSampleTime: Date? = nil
    /// The latest sample time for current samples across all types
    public var currentUploadLatestSampleTime: Date? = nil
    /// The start date for current phase uploader
    public var currentStartDate: Date? = nil
}
