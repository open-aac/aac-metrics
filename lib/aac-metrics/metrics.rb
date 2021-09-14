# TODO:
# Scores for average effort level for word sets (spelling if that's th only way)
# Effort scores for sentence corpus
# Effort algorithms for scanning/eyes
# TODO: manual way to flag button as conceptually
#       related to the same-locaed button on the
#       prior board, allowing for a discounted penalty
module AACMetrics::Metrics
  def self.analyze(obfset, output=true)
    locale = nil
    buttons = []
    total_boards = 1
    
    if obfset.is_a?(Hash) && obfset['buttons']
      locale = obfset['locale'] || 'en'
      buttons = []
      obfset['buttons'].each do |btn|
        buttons << {
          id: btn['id'],
          label: btn['label'],
          level: btn['level'],
          effort: btn['effort']
        }
      end
      total_boards = obfset['total_boards']
    else
      visited_board_ids = {}
      to_visit = [{board: obfset[0], level: 0, entry_x: 1.0, entry_y: 1.0}]
      locale = obfset[0]['locale']
      known_buttons = {}
      sqrt2 = Math.sqrt(2)
      while to_visit.length > 0
        board = to_visit.shift
        visited_board_ids[board[:board]['id']] = board[:level]
        puts board[:board]['id'] if output
        btn_height = 1.0  / board[:board]['grid']['rows'].to_f
        btn_width = 1.0  / board[:board]['grid']['columns'].to_f
        board_effort = 0
        # add effort for level of complexity when new board is rendered
        board_effort += 0.003 * board[:board]['grid']['rows'] * board[:board]['grid']['columns']
        # add effort for number of visible buttons
        board_effort += 0.007 * board[:board]['grid']['order'].flatten.length
        prior_buttons = 0

        board[:board]['grid']['rows'].times do |row_idx|
          board[:board]['grid']['columns'].times do |col_idx|
            button_id = (board[:board]['grid']['order'][row_idx] || [])[col_idx]
            button = board[:board]['buttons'].detect{|b| b['id'] == button_id }
            prior_buttons += 0.1 if !button
            next unless button
            x = (btn_width / 2)  + (btn_width * col_idx)
            y = (btn_height / 2) + (btn_height * row_idx)
            # prior_buttons = (row_idx * board[:board]['grid']['columns']) + col_idx
            effort = 0
            effort += board_effort
            # add effort for percent distance from entry point
            distance = Math.sqrt((x - board[:entry_x]) ** 2 + (y - board[:entry_y]) ** 2) / sqrt2
            effort += distance
            if distance > 0.1 || (board[:entry_x] == 1.0 && board[:entry_y] == 1.0)
              # add small effort for every prior (visible) button when visually scanning
              effort += prior_buttons * 0.001
            else
              # ..unless it's right by the previous button, then
              # add tiny effort for local scan
              effort += distance * 0.5
            end
            # add cumulative effort from previous sequence
            effort += board[:prior_effort] || 0
            prior_buttons += 1

            if button['load_board']
              try_visit = false
              # For linked buttons, only traverse if
              # the board hasn't been visited, or if 
              # we're not visiting it at a lower level
              if visited_board_ids[button['load_board']['id']] == nil
                try_visit = true 
              elsif visited_board_ids[button['load_board']['id']] > board[:level] + 1
                try_visit = true 
              end
              if to_visit.detect{|b| b[:board]['id'] == button['load_board']['id'] && b[:level] <= board[:level] + 1 }
                try_visit = false
              end
              if try_visit
                next_board = obfset.detect{|brd| brd['id'] == button['load_board']['id'] }
                puts "LIKE[] #{effort}" if button['label'] == 'like'
                if next_board
                  to_visit.push({
                    board: next_board,
                    level: board[:level] + 1,
                    prior_effort: effort + 1.0,
                    entry_x: x,
                    entry_y: y
                  })
                end
              end
            else
              word = button['label']
              existing = known_buttons[word]
              if !existing || existing[:effort] < effort #board[:level] < existing[:level]
                puts "LIKE #{effort}" if button['label'] == 'like'
                known_buttons[word] = {
                  id: "#{button['id']}::#{board[:board]['id']}",
                  label: word,
                  level: board[:level],
                  effort: effort
                }
              end
            end
          end
        end
      end
      buttons = known_buttons.to_a.map(&:last)
      total_boards = visited_board_ids.keys.length
    end
    buttons = buttons.sort_by{|b| [b[:effort] || 1, b[:label] || ""] }
    clusters = {}
    buttons.each do |btn| 
      clusters[btn[:level]] ||= []
      clusters[btn[:level]] << btn
    end
    {
      analysis_version: AACMetrics::VERSION,
      locale: locale,
      total_boards: total_boards,
      total_buttons: buttons.length,
      buttons: buttons,
      levels: clusters
    }
  end

  def self.analyze_and_compare(obfset, compset)
    target = AACMetrics::Metrics.analyze(obfset, false)
    res = {}.merge(target)

    compare = AACMetrics::Metrics.analyze(compset, false)
    res[:comp_boards] = compare[:total_boards]
    res[:comp_buttons] = compare[:total_buttons]
    
    compare_words = []
    compare_buttons = {}
    comp_efforts = {}
    compare[:buttons].each do |btn|
      compare_words << btn[:label]
      compare_buttons[btn[:label]] = btn
      comp_efforts[btn[:label]] = btn[:effort]
    end

    efforts = {}
    target_efforts = {}
    target_words = []
    res[:buttons].each{|b| 
      target_words << b[:label]
      target_efforts[b[:label]] = b[:effort]
      efforts[b[:label]] = b[:effort] 
      comp = compare_buttons[b[:label]]
      if comp
        b[:comp_level] = comp[:level]
        b[:comp_effort] = comp[:effort]
      end
    }
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
    synonyms = AACMetrics::Loader.synonyms(target[:locale])
    common_words_obj['efforts'].each{|w, e| efforts[w] ||= e }
    common_words = common_words_obj['words']
    
    too_easy = []
    too_hard = []
    target[:buttons].each do |btn|
      if btn[:effort] && common_words_obj['efforts'][btn[:label]]
        if btn[:effort] < common_words_obj['efforts'][btn[:label]] - 5
          too_easy << btn[:label]
        elsif btn[:effort] > common_words_obj['efforts'][btn[:label]] + 3
          too_hard << btn[:label]
        end
      end
    end

    
    missing = (compare_words - target_words).sort_by{|w| efforts[w] }
    missing = missing.select do |word|
      !synonyms[word] || (synonyms[word] & target_words).length == 0
    end
    extras = (target_words - compare_words).sort_by{|w| efforts[w] }
    extras = extras.select do |word|
      !synonyms[word] || (synonyms[word] & compare_words).length == 0
    end
    # puts "MISSING WORDS (#{missing.length}):"
    res[:missing_words] = missing
    # puts missing.join('  ')
    # puts "EXTRA WORDS (#{extras.length}):"
    res[:extra_words] = extras
    # puts extras.join('  ')
    overlap = (target_words & compare_words & common_words)
    # puts "OVERLAPPING WORDS (#{overlap.length}):"
    res[:overlapping_words] = overlap
    # puts overlap.join('  ')
    missing = (common_words - target_words)
    missing = missing.select do |word|
      !synonyms[word] || (synonyms[word] & target_words).length == 0
    end
    common_effort = 0
    comp_effort = 0
    common_words.each do |word|
      effort = target_efforts[word]
      if !effort && synonyms[word]
        synonyms[word].each do |syn|
          effort ||= target_efforts[syn]
        end
      end
      effort ||= 2 + (word.length * 2.5)
      common_effort += effort

      effort = comp_efforts[word]
      if !effort && synonyms[word]
        synonyms[word].each do |syn|
          effort ||= comp_efforts[syn]
        end
      end
      effort ||= 2 + (word.length * 2.5)
      comp_effort += effort
    end
    common_effort = common_effort.to_f / common_words.length.to_f
    comp_effort = comp_effort.to_f / common_words.length.to_f
    # puts "MISSING FROM COMMON (#{missing.length})"
    res[:missing] = {
      :common => {name: "Common Word List", list: missing}
    }
    res[:cores] = {
      :common => {name: "Common Word List", list: common_words, average_effort: common_effort, comp_effort: comp_effort}
    }
    # puts missing.join('  ')
    core_lists.each do |list|
      missing = []
      list_effort = 0
      comp_effort = 0
      list['words'].each do |word|
        words = [word] + (synonyms[word] || [])
        if (target_words & words).length == 0
          missing << word
        end
        effort = target_efforts[word]
        if !effort
          words.each{|w| effort ||= target_efforts[w] }
        end
        effort ||= 2 + (word.length * 2.5)
        list_effort += effort
        effort = comp_efforts[word]
        if !effort
          words.each{|w| effort ||= comp_efforts[w] }
        end
        effort ||= 2 + (word.length * 2.5)
        comp_effort += effort
      end
      if missing.length > 0
        # puts "MISSING FROM #{list['id']} (#{missing.length}):"
        res[:missing][list['id']] = {name: list['name'], list: missing, average_effort: list_effort}
        # puts missing.join('  ')
      end
      list_effort = list_effort.to_f / list['words'].length.to_f
      comp_effort = comp_effort.to_f / list['words'].length.to_f
      res[:cores][list['id']] = {name: list['name'], list: list['words'], average_effort: list_effort, comp_effort: comp_effort}
    end
    # puts "CONSIDER MAKING EASIER"
    res[:high_effort_words] = too_hard
    # puts too_hard.join('  ')
    # puts "CONSIDER LESS PRIORITY"
    res[:low_effort_words] = too_easy
    # puts too_easy.join('  ')
    res
  end
end