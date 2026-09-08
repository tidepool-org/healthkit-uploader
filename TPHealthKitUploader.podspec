Pod::Spec.new do |spec|

  spec.name         = "TPHealthKitUploader"
  spec.version      = "2.0.0"
  spec.summary      = "A framework to upload Apple HealthKit items to Tidepool."
  spec.description  = <<-DESC
  Reads HealthKit samples (blood glucose, insulin, carbs, workouts) and uploads them
  to Tidepool via TidepoolKit. Supports historical and continuous upload modes.
                   DESC

  spec.homepage     = "https://github.com/tidepool-org/healthkit-uploader"
  spec.license      = "BSD"
  spec.author       = { "Tidepool" => "support@tidepool.org" }
  spec.platform     = :ios, "15.0"
  spec.source       = { :git => "https://github.com/tidepool-org/healthkit-uploader.git", :tag => spec.version }
  spec.source_files  = 'Source/*.swift', 'Source/*/*.swift', 'Source/*/*/*.swift'
  spec.swift_version = "5.9"

  spec.dependency 'TidepoolKit', '~> 1.0'

end
