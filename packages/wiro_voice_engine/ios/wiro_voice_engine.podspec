Pod::Spec.new do |s|
  s.name             = 'wiro_voice_engine'
  s.version          = '0.1.0'
  s.summary          = "Wiro's native audio bridge for realtime conversations."
  s.description      = <<-DESC
Microphone capture and PCM playback in one shared audio graph so acoustic
echo cancellation can correlate speaker output with microphone input.
                       DESC
  s.homepage         = 'https://wiro.ai'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Wiro' => 'support@wiro.ai' }
  s.source           = { :path => '.' }
  s.source_files = 'wiro_voice_engine/Sources/wiro_voice_engine/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  s.resource_bundles = {
    'wiro_voice_engine_privacy' => [
      'wiro_voice_engine/Sources/wiro_voice_engine/PrivacyInfo.xcprivacy',
    ],
  }
end
