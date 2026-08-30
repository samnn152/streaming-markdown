Pod::Spec.new do |s|
  s.name             = 'animated_streaming_markdown'
  s.version          = '0.3.7'
  s.summary          = 'Flutter streaming Markdown parser and renderer.'
  s.description      = <<-DESC
Flutter markdown streaming package with native Tree-sitter parser bindings.
                       DESC
  s.homepage         = 'https://samnn.dev'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'samnn152' => 'https://github.com/samnn152' }

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
