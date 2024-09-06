lib_dir = File.expand_path(File.join(File.dirname(__FILE__), 'lib'))
$LOAD_PATH.unshift(lib_dir) unless $LOAD_PATH.include?(lib_dir)
require 'aac-metrics'
locale = ARGV[0] || 'en'

core_lists = AACMetrics::Loader.core_lists(locale)
cores = {}
core_lists.each do |list|
  list['words'].each do |word|
    cores[word] = true
  end
end

common = AACMetrics::Loader.common_words(locale)

common = Dir.glob(File.expand_path(File.join(File.dirname(__FILE__), 'sets', 'common_words.' + locale + '.json')))

fringes = {}
obfsets = Dir.glob(File.expand_path(File.join(File.dirname(__FILE__), 'sets', '*.' + locale + '.obfset')))
obfsets.each do |obfset|
  obf = AACMetrics::Loader.retrieve(obfset, true)
  obfset_fringes = {}
  obf.each do |brd|
    brd['buttons'].each do |btn|
      if !cores[btn['label']]
        obfset_fringes[btn['label']] = true
      end
    end
  end
  obfset_fringes.each do |word, bool|
    fringes[word] ||= 0
    fringes[word] += 1
  end
end
final_fringes = fringes.select{|word, cnt| cnt > 1}.map(&:first)
final_fringes = fringes.select{|word, cnt| cnt > 2}.map(&:first) if final_fringes.length > 3000

fringe_fn = File.expand_path(File.join(File.dirname(__FILE__), 'sets', 'fringe.' + locale + '.json'))
fringe = JSON.parse(File.read(fringe_fn))
fringe = fringe.select{|list| list['id'] != 'aggregate'}
fringe << {
  'id' => 'aggregate',
  'name' => "Aggregate Fringe",
  'locale' => locale,
  'categories' => [{
    'name' => 'all',
    'id' => 'all',
    'words' => final_fringes
  }]
}
f = File.open(fringe_fn, 'w')
f.write(JSON.pretty_generate(fringe))
f.close

puts final_fringes.to_json
puts final_fringes.length
