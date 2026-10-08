# gaiadesk_embed (iOS): a thin Flutter plugin over the GaiaDeskEmbed pod, which
# carries the Swift SDK and the prebuilt GaiaDeskEmbedFFI.xcframework.
Pod::Spec.new do |s|
  s.name             = 'gaiadesk_embed'
  s.version          = '0.1.0'
  s.summary          = 'A "Get help" button for Flutter apps: share the app\'s own screen with your support team.'
  s.description      = <<-DESC
GaiaDesk embed for Flutter on iOS: consent first, an always-visible sharing
indicator, masked regions painted out before encoding, view-only by default.
                       DESC
  s.homepage         = 'https://github.com/Gaia-Desk/gaiadesk-embed-flutter'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'GaiaDesk' => 'noreply@gaiadesk.net' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.swift'
  s.resource_bundles = { 'gaiadesk_embed_privacy' => ['Resources/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'
  s.dependency 'GaiaDeskEmbed', '~> 0.1'
  s.platform         = :ios, '15.0'

  # Flutter.framework does not contain an i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.9'
end
