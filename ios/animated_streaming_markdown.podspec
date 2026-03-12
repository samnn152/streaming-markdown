Pod::Spec.new do |s|
  s.name             = 'animated_streaming_markdown'
  s.version          = '0.0.1'
  s.summary          = 'Flutter FFI plugin exposing tree-sitter markdown language.'
  s.description      = <<-DESC
Flutter FFI plugin exposing tree-sitter markdown language.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'hider152' => 'hider152@example.com' }

  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../packages/tree-sitter/lib/include"'
  }
  s.swift_version = '5.0'
end
