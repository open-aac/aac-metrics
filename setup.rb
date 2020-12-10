lib_dir = File.expand_path(File.join(File.dirname(__FILE__), 'lib'))
$LOAD_PATH.unshift(lib_dir) unless $LOAD_PATH.include?(lib_dir)
require 'aac-metrics'

# require 'obf'
# path = "./sets/links.obz"
# ext = OBF::OBZ.to_external(path, {})
# obfset = AACMetrics::Loader.retrieve(ext)
# target = AACMetrics::Metrics.analyze(obfset)

obfset1 = AACMetrics::Loader.retrieve(ARGV[0])
obfset2 = AACMetrics::Loader.retrieve(ARGV[1] || 'qc24')

puts ARGV[0]
puts ARGV[1]
res = AACMetrics::Metrics.analyze_and_compare(obfset1, obfset2)

res[:levels].each do |level, buttons|
  puts "HITS: #{level + 1}"
  puts buttons.map{|b| b[:label] }.join('  ')
end
puts "TOTAL BOARDS: #{res[:total_boards]}"
puts "TOTAL WORDS: #{res[:total_words]}"

puts "MISSING WORDS (#{res[:missing_words].length}):"
puts res[:missing_words].join('  ')
puts "EXTRA WORDS (#{res[:extra_words].length}):"
puts res[:extra_words].join('  ')
puts "OVERLAPPING WORDS (#{res[:overlapping_words].length}):"
puts res[:overlapping_words].join('  ')
res[:missing].each do |id, obj|
  puts "MISSING FROM #{obj[:name]} (#{res[:missing][id][:list].length})"
  puts res[:missing][id][:list].join('  ')
end
puts "CONSIDER MAKING EASIER"
puts res[:high_effort_words].join('  ')
puts "CONSIDER LESS PRIORITY"
puts res[:low_effort_words].join('  ')
res[:cores].each do |id, obj|
  puts "SCORE FOR #{obj[:name]} #{obj[:average_effort]} vs. #{obj[:comp_effort]}"
end

