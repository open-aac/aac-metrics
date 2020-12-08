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
        board_effort += 0.005 * board[:board]['grid']['rows'] * board[:board]['grid']['columns']
        # add effort for number of visible buttons
        board_effort += 0.01 * board[:board]['grid']['order'].flatten.length

        board[:board]['grid']['rows'].times do |row_idx|
          board[:board]['grid']['columns'].times do |col_idx|
            button_id = (board[:board]['grid']['order'][row_idx] || [])[col_idx]
            button = board[:board]['buttons'].detect{|b| b['id'] == button_id }
            next unless button
            x = (btn_width / 2)  + (btn_width * col_idx)
            y = (btn_height / 2) + (btn_height * row_idx)
            prior_buttons = (row_idx * board[:board]['grid']['columns']) + col_idx
            effort = 0
            effort += board_effort
            # add effort for percent distance from entry point
            distance = Math.sqrt((x - board[:entry_x]) ** 2 + (y - board[:entry_y]) ** 2) / sqrt2
            effort += distance
            if distance > 0.1 || (board[:entry_x] == 1.0 && board[:entry_y] == 1.0)
              # add small effort for every prior button when visually scanning
              effort += prior_buttons * 0.05
            else
              # ..unless it's right by the previous button, then
              # add tiny effort for local scan
              effort += distance * 0.5
            end
            # add cumulative effort from previous sequence
            effort += board[:prior_effort] || 0
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
              if !existing || board[:level] < existing[:level]
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
    
    compare_words = []
    compare_buttons = {}
    compare_words = compare[:buttons].each do |btn|
      compare_words << btn[:label]
      compare_buttons[btn[:label]] = btn
    end

    efforts = {}
    target_words = []
    res[:buttons].each{|b| 
      target_words << b[:label]
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
    extras = (target_words - compare_words).sort_by{|w| efforts[w] }
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
    # puts "MISSING FROM COMMON (#{missing.length})"
    res[:missing] = {
      :common => {name: "Common Word List", list: missing}
    }
    # puts missing.join('  ')
    core_lists.each do |list|
      missing = []
      list['words'].each do |word|
        words = word.gsub(/’/, '').downcase.split(/\|/)
        if (target_words & words).length == 0
          missing << words[0] 
        end
      end
      if missing.length > 0
        # puts "MISSING FROM #{list['id']} (#{missing.length}):"
        res[:missing][list['id']] = {name: list['name'], list: missing}
        # puts missing.join('  ')
      end
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