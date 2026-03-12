Pod::Spec.new do |s|
  s.name             = 'streaming_markdown'
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
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../packages/tree-sitter/lib/include"'
  }
  s.swift_version = '5.0'
end
