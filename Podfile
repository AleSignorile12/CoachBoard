platform :ios, '26.0'
# No input/output file lists on the CocoaPods script phases: the Mac app (Mac Catalyst) skips them, and missing
# listed files would stop its build.
install! 'cocoapods', :disable_input_output_paths => true

target 'Tracker' do
  use_frameworks!
  # Offline translation (Apple's Translation framework has no Croatian). iPhone only: ML Kit has no Mac version.
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

# The Mac app is built without any pod (ML Kit ships for iPhone only): no pod frameworks are searched, linked or
# embedded when building for Mac Catalyst. The app links Pods_Tracker.framework only for iOS (platform filter).
post_integrate do |installer|
  support = File.join(installer.sandbox.root, 'Target Support Files', 'Pods-Tracker')
  Dir.glob(File.join(support, 'Pods-Tracker.*.xcconfig')).each do |path|
    text = File.read(path)
    next if text.include?('[sdk=macosx*]')
    text << "\n// Mac app (Mac Catalyst): no pods.\n"
    %w[FRAMEWORK_SEARCH_PATHS HEADER_SEARCH_PATHS LIBRARY_SEARCH_PATHS OTHER_LDFLAGS OTHER_SWIFT_FLAGS].each do |key|
      text << "#{key}[sdk=macosx*] =\n"
    end
    File.write(path, text)
  end
  %w[frameworks resources].each do |kind|
    script = File.join(support, "Pods-Tracker-#{kind}.sh")
    next unless File.exist?(script)
    text = File.read(script)
    next if text.include?('maccatalyst')
    text.sub!("#!/bin/sh\n", "#!/bin/sh\n# Mac app: no pod #{kind} to copy.\n[ \"${EFFECTIVE_PLATFORM_NAME:-}\" = \"-maccatalyst\" ] && exit 0\n")
    File.write(script, text)
  end
end
