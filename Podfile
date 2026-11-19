platform :ios, '26.0'

target 'Tracker' do
  use_frameworks!
  # Offline translation (Apple's Translation framework has no Croatian).
  pod 'GoogleMLKit/Translate'
end

# Some pods still declare iOS 9-12, which Xcode 27 refuses to build.
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.5'
    end
  end
end
