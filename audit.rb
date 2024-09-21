lib_dir = File.expand_path(File.join(File.dirname(__FILE__), 'lib'))
$LOAD_PATH.unshift(lib_dir) unless $LOAD_PATH.include?(lib_dir)
require 'aac-metrics'

# require 'obf'
# path = "./sets/links.obz"
# ext = OBF::OBZ.to_external(path, {})
# obfset = AACMetrics::Loader.retrieve(ext)
# target = AACMetrics::Metrics.analyze(obfset)

all = Dir.glob(File.expand_path(File.join(File.dirname(__FILE__), 'sets', '*.obfset')))

res = []
ref_obfset = AACMetrics::Loader.retrieve('pc36') 
all.each do |fn|
  key = fn.split(/\//)[-1].split(/-/)[0]
  next if key.match(/\.obfset/)
  puts key
  obfset = AACMetrics::Loader.retrieve(key) 
  analysis = AACMetrics::Metrics.analyze_and_compare(obfset, ref_obfset)
  res << [key, analysis[:target_effort_score], analysis[:care_components]]
end
puts "set\tscore\t\tcore\tfringe\tsent.\tcommon fringe"
res.sort_by{|k, s, care| s }.reverse.each do |k, s, care|
  puts "#{k}\t#{s.round(1)}\t\t#{care[:core].round}\t#{care[:fringe].round}\t#{care[:sentences].round}\t#{care[:common_fringe].round}"
end
