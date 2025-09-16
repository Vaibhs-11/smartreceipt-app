# flutter ios podhelper

def install_all_flutter_pods(flutter_application_path = nil)
  flutter_application_path ||= File.dirname(File.dirname(File.realpath(__FILE__)))
  symlinks_dir = File.join(flutter_application_path, '.symlinks')
  FileUtils.mkdir_p(symlinks_dir)

  flutter_podhelper = File.join(flutter_application_path, '.ios', 'Flutter', 'podhelper.rb')
  if File.exist?(flutter_podhelper)
    eval(File.read(flutter_podhelper), binding)
  else
    puts "Warning: Missing internal Flutter podhelper at #{flutter_podhelper}"
  end
end

def flutter_additional_ios_build_settings(target)
  target.build_configurations.each do |config|
    # Ensure simulator builds exclude arm64
    config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'arm64'
  end
end
