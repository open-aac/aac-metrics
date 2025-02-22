# USAGE ruby setup.rb obfset1 obfset2 (blank|export|render)
#   render will update sets/preview.html to show obfset1
# Analyzes and compares two data sets. Optionally exports
# the minimal obfset to export.json for easier access. 
lib_dir = File.expand_path(File.join(File.dirname(__FILE__), 'lib'))
$LOAD_PATH.unshift(lib_dir) unless $LOAD_PATH.include?(lib_dir)
require 'aac-metrics'

obfset1 = AACMetrics::Loader.retrieve(ARGV[0])
obfset2 = AACMetrics::Loader.retrieve(ARGV[1] || 'qc24')

puts ARGV[0]
puts ARGV[1]
res = AACMetrics::Metrics.analyze_and_compare(obfset1, obfset2, (ARGV[2] == 'export' || ARGV[2] == 'render'))

res[:levels].each do |level, buttons|
  puts "HITS: #{level + 1}"
  puts buttons.map{|b| b[:label] }.join('  ')
end
puts "TOTAL BOARDS: #{res[:total_boards]}"
puts "TOTAL BUTTONS: #{res[:total_buttons]}"
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
  puts "SCORE FOR #{obj[:name]} #{obj[:average_effort].round(2)} vs. #{obj[:comp_effort].round(2)}"
end

puts ""
res[:sentences].each do |sentence|
  str = "SCORE FOR #{sentence[:sentence]} #{sentence[:effort].round(2)}"
  str += "*" if sentence[:typing]
  str +=  " vs #{sentence[:comp_effort].round(2)}"
  str += "*" if sentence[:comp_typing]
  puts str
end

puts ""
puts "#{ARGV[0]} #{res[:target_effort_score].round(2)}"
puts "#{ARGV[1] || 'qc24'} #{res[:comp_effort_score].round(2)}"

if ARGV[2] == 'export'
  output = File.expand_path(File.join(File.dirname(__FILE__), 'export.json'))
  f = File.open(output, 'w')
  f.write(JSON.pretty_generate(res[:obfset]))
  f.close
elsif ARGV[2] == 'render'
  html = File.read('./sets/preview.html')
  pre, pad = html.split("<!-- START JSON -->")
  mid, pst  = pad.split("<!-- END JSON -->")
  html = pre + "\n<!-- START JSON -->\n"
  res[:name] = ARGV[0]
  html += "<script>\nwindow.vocab = " + res.to_json + ";\n</script>\n"
  html += "\n<!-- END JSON -->\n"
  html += pst
  f = File.open("./sets/preview.html", 'w')
  f.puts html
  f.close
  res[:obfset].each_with_index do |board, idx|
    if idx == 0 || (ARGV[3] && board['id'] == ARGV[3])
      puts "\n\n"
      board['grid']['order'].each do |row|
        row_str = ""
        row.each do |col|
          btn = col && board['buttons'].detect{|b| b['id'] == col}
          if btn
            str = btn['label']
            if btn['effort']
              str += " (#{btn['effort'].round(1)})"
            end
            row_str += str + "\t"
          else
            row_str += "_" + "\t"
          end
        end
        puts row_str
      end
    end
  end
end
# puts JSON.pretty_generate(res[:sentences])

