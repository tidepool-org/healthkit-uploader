Pod::Spec.new do |spec|

  spec.name         = "TPHealthKitUploader"
  spec.version      = "0.9.2"
  spec.summary      = "A framework to upload Apple HealthKit items to Tidepool."
  spec.description  = <<-DESC
  Initialized with a call-back protocol to provide the framework login context, this provides an interface to 
  initialize HealthKit for the app, to upload historical HealthKit samples, and to continuously upload new current samples.
  Current sample types supported are blood glusose, insulin, carbs, and workouts.
                   DESC

  spec.homepage     = "https://github.com/tidepool-org/healthkit-uploader"
  spec.license      = "BSD"
  spec.author       = { "Larry" => "larry@tidepool.org" }
  spec.platform     = :ios, "11.0"
  spec.source       = { :git => "https://github.com/tidepool-org/healthkit-uploader.git", :tag => spec.version }
  spec.source_files  = 'Source/*.swift', 'Source/*/*.swift', 'Source/*/*/*.swift'
  spec.swift_version = "4.2"

end
