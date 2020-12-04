lib_dir = File.expand_path(File.join(File.dirname(__FILE__), 'lib'))
$LOAD_PATH.unshift(lib_dir) unless $LOAD_PATH.include?(lib_dir)
require 'aac-metrics'

obfset = AACMetrics::Loader.retrieve(ARGV[0])
target = AACMetrics::Metrics.analyze(obfset)

obfset = AACMetrics::Loader.retrieve(ARGV[1] || 'l84f')
compare = AACMetrics::Metrics.analyze(obfset, false)

# TODO: compare priority order, highlight buttons that
# are out of expected order compared to common

target_words = target[:buttons].map{|b| b[:label] }
compare_words = compare[:buttons].map{|b| b[:label] }
efforts = {}
target[:buttons].each{|b| efforts[b[:label]] = b[:effort] }
compare[:buttons].each{|b| 
  if efforts[b[:label]]
    efforts[b[:label]] += b[:effort] 
    efforts[b[:label]] /= 2
  else
    efforts[b[:label]] ||= b[:effort] 
  end
}

core_lists = AACMetrics::Loader.core_lists(target[:locale])
common_words_obj = AACMetrics::Loader.common_words(target[:locale])
common_words_obj['efforts'].each{|w, e| efforts[w] ||= e }
common_words = common_words_obj['words']

too_easy = []
too_hard = []
target[:buttons].each do |btn|
  puts "#{btn[:effort]} #{common_words_obj['efforts'][btn[:label]]}"
  if btn[:effort] && common_words_obj['efforts'][btn[:label]]
    if btn[:effort] < common_words_obj['efforts'][btn[:label]] - 5
      too_easy << btn[:label]
    elsif btn[:effort] > common_words_obj['efforts'][btn[:label]] + 3
      too_hard << btn[:label]
    end
  end
end

missing = (compare_words - target_words).sort_by{|w| efforts[w] }
extras = (target_words - compare_words).sort_by{|w| efforts[w] }
puts "MISSING WORDS (#{missing.length}):"
puts missing.join('  ')
puts "EXTRA WORDS (#{extras.length}):"
puts extras.join('  ')
overlap = (target_words & compare_words & common_words)
puts "OVERLAPPING WORDS (#{overlap.length}):"
puts overlap.join('  ')
missing = (common_words - target_words)
puts "MISSING FROM COMMON (#{missing.length})"
puts missing.join('  ')
core_lists.each do |list|
  missing = []
  list['words'].each do |word|
    words = word.gsub(/’/, '').downcase.split(/\|/)
    if (target_words & words).length == 0
      missing << words[0] 
    end
  end
  # missing = list['words'].map(&:downcase) - target_words
  if missing.length > 0
    puts "MISSING FROM #{list['id']} (#{missing.length}):"
    puts missing.join('  ')
  end
end
puts "CONSIDER MAKING EASIER"
puts too_hard.join('  ')
puts "CONSIDER LESS PRIORITY"
puts too_easy.join('  ')