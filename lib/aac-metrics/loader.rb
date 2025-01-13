require 'json'
require 'typhoeus'
require 'digest'

module AACMetrics::Loader
  def self.retrieve(obfset, unsub=true)
    if obfset.is_a?(Hash) && obfset['boards']
      json = []
      obfset['boards'].each do |board|
        new_board = {
          "id" => board['id'],
          "buttons" => [],
          "locale" => board['locale'] || 'en',
          "grid" => board['grid'],
        }
        board['buttons'].each do |button|
          new_button = {
            "label" => ((button['vocalization'] || '').length > 0 ? button['vocalization'] : button['label']).to_s.downcase.gsub(/’/, ''),
            "id" => button['id']
          }
          if button['load_board'] && button['load_board']['id']
            new_button['load_board'] = {'id' => button['load_board']['id']}
            new_button['load_board']['temporary_home'] = button['load_board']['temporary_home'] if button['load_board']['temporary_home'] == true || button['load_board']['temporary_home'] == 'prior'
            new_button['load_board']['add_to_sentence'] = true if button['load_board']['add_to_sentence']
          end
          new_board['buttons'].push(new_button)
        end
        json << new_board
      end
    elsif obfset.match(/^http/)
      res = Typhoeus.get(obfset, timeout: 10)
      json = JSON.parse(res.body)
    elsif !obfset.match(/\.obfset/)
      fn = obfset
      obfset = Dir.glob(File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'sets', fn + '*.obfset')))[0]
      analysis = nil
      if !obfset
        analysis = Dir.glob(File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'sets', fn + '*.analysis')))[0]
      end
      if obfset
        json = JSON.parse(File.read(obfset))
        relations_hash = {}
        json.each do |board|
          board['grid']['order'].each_with_index do |row, row_idx|
            row.each_with_index do |id, col_idx|
              button = id && board['buttons'].detect{|b| b['id'] == id }
              if button && button['label'] && !button['clone_id']
                ref = "#{board['grid']['rows']}x#{board['grid']['columns']}-#{row_idx}.#{col_idx}"
                pre = 'c'
                relations_hash["cpre#{ref}-#{button['label']}"] ||= []
                relations_hash["cpre#{ref}-#{button['label']}"] << [board, button]
              end
            end
          end
        end
        relations_hash.each do |id, cells|
          if cells.length > 1
            cells.each do |board, button|
              board['clone_ids'] ||= []
              board['clone_ids'] << id
              button['clone_id'] ||= id
            end
          end
        end
      elsif analysis
        json = JSON.parse(File.read(analysis))
      end
    else
      json = JSON.parse(File.read(obfset))
    end
    if unsub
      locale = json.is_a?(Array) ? json[0]['locale'] : json['locale']
      base = self.base_words(locale)
      if json.is_a?(Array)
        json.each do |brd|
          brd['buttons'].each do |btn|
            if (btn['label'] || '').match(/^\$/)
              word = base[btn['label'].sub(/^\$/, '')]
              btn['label'] = word if word
            end
            btn['label'] = (btn['label'] || '').gsub(/’/, '')
          end
        end
      elsif json.is_a?(Hash)
        (json['buttons'] || []).each do |button|
          if button['label'].match(/^\$/)
            word = base[button['label'].sub(/^\$/, '')]
            button['label'] = word if word
          end
          button['label'] = button['label'].gsub(/’/, '')
        end
      end
    end
    json
  end

  def self.process(fn, token=nil, add_words=false)
    paths = [fn]
    boards = []
    visited_paths = {}
    queued_paths = {}
    idx = 1
    words_path = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'sets', "base_words"))
    words = nil
    do_ingest = true
    relations_hash = {}
    
    while paths.length > 0
      path = paths.shift
      visited_paths[path] = idx
      new_json = {
        "format" => 'obs',
        "id" => "brd#{idx}",
        "buttons" => [],
        "grid" => {},
      }
      idx += 1
      json = nil
      if path.match(/^http/)
        if token
          path += "?access_token=#{token}"
        end
        req = Typhoeus.get(path, timeout: 10)
        json = JSON.parse(req.body)
        # puts path
      else
        if !File.exist?(path)
          orig_path = path
          path = File.expand_path(File.join(fn, "..", orig_path))
          if !File.exist?(path)
            path = File.expand_path(File.join(fn, "..", "..", orig_path))
          end
        end
        # puts "#{path}"
        json = JSON.parse(File.read(path))
      end
      if json && json['grid']
    #    puts JSON.pretty_generate(json)
        new_json['locale'] = json['locale'] || 'en'
        if !words
          words_path = words_path + "." + new_json['locale'].split(/-|_/)[0] + ".json"
          words = JSON.parse(File.read(words_path))
        end
        btn_idx = 1
        new_json['grid']['rows'] = json['grid']['rows']
        new_json['grid']['columns'] = json['grid']['columns']
        new_json['grid']['order'] = []
        new_json['grid']['rows'].times do |row_idx|
          row = json['grid']['order'][row_idx] || []
          new_row = []
          new_json['grid']['columns'].times do |col_idx|
            btn_id = row[col_idx]
            btn = json['buttons'].detect{|b| btn_id && b['id'] == btn_id }
            new_btn = nil
            if btn
              new_btn = {
                "id" => "btn#{btn_idx}",
                "label" => (btn['vocalization'] || '').length > 0 ? btn['vocalization'] : btn['label']
              }
              # record load_board reference
              btn_idx += 1
              if btn['load_board']
                if !btn['load_board']['path'] && btn['load_board']['id']
                  bpath = File.join(File.dirname(path), btn['load_board']['id'] + '.obf')
                  if File.exists?(bpath)
                    btn['load_board']['path'] = bpath
                  end
                end
                if btn['load_board']['path']
                  if visited_paths[btn['load_board']['path']]
                    new_btn['load_board'] = {'id' => "brd#{visited_paths[btn['load_board']['path']]}"}
                  else
                    paths.push(btn['load_board']['path']) unless queued_paths[btn['load_board']['path']]
                    queued_paths[btn['load_board']['path']] = true
                    new_btn['load_board'] = {'tmp_path' => btn['load_board']['path']}
                  end
                elsif btn['load_board']['data_url']
                  if visited_paths[btn['load_board']['data_url']]
                    new_btn['load_board'] = {'id' => "brd#{visited_paths[btn['load_board']['data_url']]}"}
                  else
                    paths.push(btn['load_board']['data_url']) unless queued_paths[btn['load_board']['data_url']]
                    queued_paths[btn['load_board']['data_url']] = true
                    new_btn['load_board'] = {'tmp_path' => btn['load_board']['data_url']}
                  end
                else
                  puts path
                  puts "Link found with no access #{btn['load_board'].to_json}"
                end
                new_btn['load_board']['temporary_home'] = true if new_btn['load_board'] && btn['load_board']['temporary_home']
                new_btn['load_board']['temporary_home'] = true if new_btn['load_board'] && btn['ext_coughdrop_home_lock']
                new_btn['load_board']['add_to_sentence'] = true if new_btn['load_board'] && btn['load_board']['add_to_sentence']
                new_btn['load_board']['add_to_sentence'] = true if new_btn['load_board'] && btn['ext_coughdrop_add_to_vocalization']
                new_btn['load_board']['add_to_sentence'] = true if new_btn['load_board'] && btn['ext_coughdrop_add_vocalization']
              elsif btn['action']
                # TODO: track keyboard actions and don't
                # treat action buttons for metrics
                new_btn = nil
              end
              # temporarily save semantic_id and possibly clone_id for later use
              # 1. Buttons in the same location with the same
              # semantic_id should be marked in the obfset as having
              # the same semantic_id
              # 2. Buttons in the same location with the same label & voc
              # and same load_board setting
              # should be marked in the obfset as having the same clone_id
              ref = "#{new_json['grid']['rows']}x#{new_json['grid']['columns']}-#{row_idx}.#{col_idx}"
              if btn['semantic_id']
                relations_hash["s#{ref}-#{btn['semantic_id']}"] ||= []
                relations_hash["s#{ref}-#{btn['semantic_id']}"] << [new_json['id'], new_btn['id']]
              end
              if new_btn && new_btn['label']
                #pre = new_btn['load_board'] ? 'cl' : 'c'
                pre = 'c'
                relations_hash["#{pre}#{ref}-#{new_btn['label']}"] ||= []
                relations_hash["#{pre}#{ref}-#{new_btn['label']}"] << [new_json['id'], new_btn['id']]
              end
              if do_ingest && new_btn && new_btn['label']
                str = new_btn['label'].downcase.sub(/^\s+/, '').sub(/\s+$/, '')
                if str.scan(/\s+/).length < 2
                  word_hash = Digest::MD5.hexdigest(str)[0, 10]
                  # Will need to re-evaluate hash process if it ever finds a collision with an already-saved word
                  raise "collision!" if words[word_hash] && words[word_hash] != str
                  if add_words || words[word_hash]
                    words[word_hash] = str
                    new_btn['label'] = "$#{word_hash}"
                  end
                end
              end

            end
            new_row.push(new_btn ? new_btn['id'] : nil)
            new_json['buttons'].push(new_btn) if new_btn
          end
          new_json['grid']['order'].push(new_row)
        end
        boards << new_json
      end
    end
    # finalize all board paths once done iterating
    boards.each do |brd|
      brd['buttons'].each do |btn|
        if btn['load_board'] && btn['load_board']['tmp_path']
          btn['load_board']['id'] = "brd#{visited_paths[btn['load_board']['tmp_path']]}" if visited_paths[btn['load_board']['tmp_path']]
          btn['load_board'].delete('tmp_path')
        end
      end
    end
    # any semantic_id or clone_id repeats must be recorded
    relations_hash.each do |id, btns|
      if btns && btns.length > 1
        btns.each do |brd_id, btn_id|
          brd = boards.detect{|b| b['id'] == brd_id }
          if brd && brd['buttons']
            btn = brd['buttons'].detect{|b| b['id'] == btn_id }
            if btn
              if id.match(/^s/)
                btn['semantic_id'] = id
                brd['semantic_ids'] ||= []
                brd['semantic_ids'] << id
              elsif id.match(/^c/)
                btn['clone_id'] = id
                brd['clone_ids'] ||= []
                brd['clone_ids'] << id
              end
            end
          end
        end
        # 
      end
    end
    # TODO: record whether the board set is expected to have auto-home
    {boards: boards, words: words, words_path: words_path}
  end

  def self.ingest(fn, token=nil)
    output = nil
    boards = nil
    if fn.match(/manifest.json/)
      json = JSON.parse(File.read(fn))
      root_fn = json['root']
      fn = fn.sub(/manifest.json/, root_fn)
    end
    if fn.match(/\.obfset$/)
      boards = retrieve(fn, false)
      output = fn
    else
      content = process(fn, token, true)
      boards = content[:boards]
      words = content[:words]
      words_path = content[:words_path]
      output_fn = Digest::MD5.hexdigest(Time.now.to_i.to_s + rand(9999).to_s)[0, 10] + ".obfset"
      output = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'sets', output_fn))
      f = File.open(output, 'w')
      f.write(JSON.pretty_generate(boards))
      f.close
      if words
        new_words = {}
        words.to_a.sort_by{|h, w| w }.each{|h, w| new_words[h] = w }
        f = File.open(words_path, 'w')
        f.write(JSON.pretty_generate(new_words))
        f.close
      end
    end
    if boards
      analysis = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'sets', output.sub(/\.obfset$/, '.analysis')))
      analysis = output.sub(/\.obfset$/, '.analysis')
      res = AACMetrics::Metrics.analyze(boards, false)
      f = File.open(analysis, 'w')
      f.write(JSON.pretty_generate(res))
      f.close
    end
    output
  end

  def self.core_lists(locale)
    locale = locale.split(/-|_/)[0]
    @@core_lists ||= {}
    return @@core_lists[locale] if @@core_lists[locale]
    path = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'sets', "core_lists.#{locale}.json"))    
    res = JSON.parse(File.read(path))
    @@core_lists[locale] = res
  end

  def self.common_words(locale)
    locale = locale.split(/-|_/)[0]
    common_paths = Dir.glob(File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'sets', "*.common.#{locale}.obfset")))
    files = common_paths.map{|p| File.basename(p) }.sort
    common_analysis_paths = Dir.glob(File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'sets', "*.common.#{locale}.analysis")))
    files += common_analysis_paths.map{|p| File.basename(p) }.sort
    path = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'sets', "common_words.#{locale}.json"))    
    res = JSON.parse(File.read(path)) rescue nil
    if !res || res['version'] != AACMetrics::VERSION || res['files'] != files
      efforts = {}
      common_words = nil
      common_paths.each do |path|
        obfset = AACMetrics::Loader.retrieve(path)
        common = AACMetrics::Metrics.analyze(obfset, false)
        common[:buttons].each{|b| 
          efforts[b[:label]] ||= []
          efforts[b[:label]] << b[:effort] 
        }
        words = common[:buttons].map{|b| b[:label] }.map{|w| w.gsub(/’/, '') }
        common_words ||= words
        common_words &= words
      end
      common_words -= ['']
      efforts.each do |word, vals|
        if vals.length == common_paths.length
          efforts[word] = vals.sum.to_f / vals.length
        else
          efforts.delete(word)
        end
      end
      sorted_efforts = {}
      efforts.to_a.sort_by(&:last).each do |str, val|
        sorted_efforts[str] = val
      end
      res = {
        'version' => AACMetrics::VERSION,
        'files' => files,
        'words' => sorted_efforts.keys,
        'efforts' => sorted_efforts
      }
      f = File.open(path, 'w')
      f.puts JSON.pretty_generate(res)
      f.close
    end
    res
  end

  def self.synonyms(locale)
    @@synonyms ||= {}
    return @@synonyms[locale] if @@synonyms[locale]
    locale = locale.split(/-|_/)[0]
    path = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'sets', "synonyms.#{locale}.json"))
    res = {}
    list = JSON.parse(File.read(path))
    list.each do |words|
      words.each do |word|
        res[word] = words - [word]
      end
    end
    @@synonyms[locale] = res
  end

  def self.sentences(locale)
    @@sentences ||= {}
    return @@sentences[locale] if @@sentences[locale]
    locale = locale.split(/-|_/)[0]
    path = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'sets', "sentences.#{locale}.json"))
    res = JSON.parse(File.read(path))
    @@sentences[locale] = res
  end

  def self.fringe_words(locale)
    @@fringe_words ||= {}
    return @@fringe_words[locale] if @@fringe_words[locale]
    locale = locale.split(/-|_/)[0]
    path = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'sets', "fringe.#{locale}.json"))
    all_words = []
    list = JSON.parse(File.read(path))
    list.each do |set|
      set['categories'].each do |cat|
        all_words += cat['words']
      end
    end
    all_words.uniq!
    @@fringe_words[locale] = all_words
  end

  def self.common_fringe_words(locale)
    @@common_fringe_words ||= {}
    return @@common_fringe_words[locale] if @@common_fringe_words[locale]
    common = self.common_words(locale)['words']
    core = self.core_lists('en').map{|r| r['words'] }.flatten.compact.uniq
    all_words = common - core
    @@common_fringe_words[locale] = all_words
  end

  def self.base_words(locale)
    @@base_words ||= {}
    return @@base_words[locale] if @@base_words[locale]
    locale = locale.split(/-|_/)[0]
    path = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'sets', "base_words.#{locale}.json"))
    res = JSON.parse(File.read(path))
    @@base_words[locale] = res
  end
end