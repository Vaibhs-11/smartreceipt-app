Pod::Spec.new do |s|
  s.name         = 'gRPC-Core'
  s.version      = '1.62.0'
  s.summary      = 'Stub replacement for gRPC-Core (header-only)'
  s.description  = 'Provides minimal headers so gRPC-C++ compiles without pulling real gRPC-Core sources.'
  s.homepage     = 'https://example.com'
  s.license      = { :type => 'MIT', :text => 'Stub podspec' }
  s.author       = { 'Stub' => 'stub@example.com' }
  s.platform     = :ios, '12.0'
  #s.source       = { :git => 'https://example.com/empty.git', :tag => s.version.to_s }
  s.source       = { :path => "." }

  s.source_files        = "include/**/*.h"
  s.public_header_files = "include/**/*.h"
  s.header_mappings_dir = "include"
end
