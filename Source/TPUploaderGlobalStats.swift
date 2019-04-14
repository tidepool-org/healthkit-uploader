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

    init(lastUpload: Date?, totalHistDays: Int, currentHistDay: Int) {
        self.lastSuccessfulCurrentUploadTime = lastUpload
        self.currentDayHistorical = currentHistDay
        self.totalDaysHistorical = totalHistDays
    }
    
    // Stats for uploading current samples:
    public var lastSuccessfulCurrentUploadTime: Date? = nil
    
    // Stats for uploading historical samples:
    /// The number of days between the earliest HK sample (across all types) and the historical/current date boundary (samples after the boundary are handled by the current anchor query).
    public var totalDaysHistorical = 0
    /// The number of days between the earliest HK sample uploaded in the historical upload and the historical/current date boundary.
    public var currentDayHistorical = 0
}
