# TODO:
# Scores for average effort level for word sets (spelling if that's th only way)
# Effort scores for sentence corpus
# Effort algorithms for scanning/eyes
# TODO: manual way to flag button as conceptually
#       related to the same-locaed button on the
#       prior board, allowing for a discounted penalty
module AACMetrics::Metrics
    # TODO: 
    # 1. When navigating from one board to the next, grid locations
    # with the same clone_id or semantic_id should result in a
    # discount to overall search based more on the number of
    # uncloned/unsemantic buttons than the number of total buttons
    # (perhaps also factoring in the percent of board with that
    # id present in the full board set)
    # 2. When selecting a button with a semantic_id or clone_id,
    # a discount to both search and selection should
    # be applied based on the percent of boards that
    # contain the same id at that grid location
    # 3.5 When selecting a button with a semantic_id or clone_id,
    # if the same id was present on the previous board,
    # an additional discount to search and selection should be applied
    def self.analyze(obfset, output=true)
    locale = nil
    buttons = []
    refs = {}
    grid = {}

    if obfset.is_a?(Hash) && obfset['buttons']
      locale = obfset['locale'] || 'en'
      refs = obfset['reference_counts']
      grid = obfset['grid']
      buttons = []
      obfset['buttons'].each do |btn|
        buttons << {
          id: btn['id'],
          label: btn['label'],
          level: btn['level'],
          effort: btn['effort'],
          semantic_id: btn['semantic_id'],
          clone_id: btn['clone_id']
        }
      end
      total_boards = obfset['total_boards']
    else
      visited_board_ids = {}
      to_visit = [{board: obfset[0], level: 0, entry_x: 1.0, entry_y: 1.0}]
      refs = {}
      rows_tally = 0.0
      cols_tally = 0.0
      root_rows = nil
      root_cols = nil
      obfset.each do |board|
        root_rows ||= board['grid']['rows']
        root_cols ||= board['grid']['columns']
        rows_tally += board['grid']['rows']
        cols_tally += board['grid']['columns']
        # determine frequency within the board set
        # for each semantic_id and clone_id
        if board['clone_ids']
          boards['clone_ids'].each do |id|
            refs[id] ||= 0
            refs[id] += 1
          end
        end
        if board['semantic_ids']
          boards['semantic_ids'].each do |id|
            refs[id] ||= 0
            refs[id] += 1
          end
        end
      end
      if (rows_tally / obfset.length.to_f - root_rows).abs > 3 || (cols_tally / obfset.length.to_f - root_cols).abs > 3
        root_rows = (rows_tally / obfset.length.to_f).floor
        root_cols = (cols_tally / obfset.length.to_f).floor
      end
      pcts = {}
      refs.each do |id, cnt|
        pcts[id] = cnt.to_f / obfset.length.to_f
      end
      locale = obfset[0]['locale']
      known_buttons = {}
      while to_visit.length > 0
        board = to_visit.shift
        visited_board_ids[board[:board]['id']] = board[:level]
        puts board[:board]['id'] if output
        btn_height = 1.0  / board[:board]['grid']['rows'].to_f
        btn_width = 1.0  / board[:board]['grid']['columns'].to_f
        board_effort = 0
        # add effort for level of complexity when new board is rendered
        button_size = button_size_effort(board[:board]['grid']['rows'], board[:board]['grid']['columns'])
        board_effort += button_size
        # add effort for number of visible buttons
        field_size = field_size_effort(board[:board]['grid']['order'].flatten.length)
        board_effort += field_size
        # decrease effort here for every button on the board
        # whose semantic_id or clone_id is repeated in the board set
        #       -0.0025 (* pct of matching boards) for semantic_id
        #       -0.005 (* pct of matching boards) for clone_id
        board[:board]['grid']['rows'].times do |row_idx|
          board[:board]['grid']['columns'].times do |col_idx|
            button_id = (board[:board]['grid']['order'][row_idx] || [])[col_idx]
            button = board[:board]['buttons'].detect{|b| b['id'] == button_id }
            if button && button['clone_id'] && pcts[button['clone_id']]
              board_effort -= 0.005 * pcts[button['clone_id']]
            elsif button && button['semantic_id'] && pcts[button['semantic_id']]
              board_effort -= 0.0025 * pcts[button['semantic_id']]
            end
          end
        end

        prior_buttons = 0

        board[:board]['grid']['rows'].times do |row_idx|
          board[:board]['grid']['columns'].times do |col_idx|
            button_id = (board[:board]['grid']['order'][row_idx] || [])[col_idx]
            button = board[:board]['buttons'].detect{|b| b['id'] == button_id }
            # prior_buttons += 0.1 if !button
            next unless button
            x = (btn_width / 2)  + (btn_width * col_idx)
            y = (btn_height / 2) + (btn_height * row_idx)
            # prior_buttons = (row_idx * board[:board]['grid']['columns']) + col_idx
            effort = 0
            # TODO: additional discount on board search effort
            #       if this button's semantic_id or clone_id
            #       was also present on the prior board
            #       board_effort * 0.5 for semantic_id
            #       board_effort * 0.33 for clone_id
            effort += board_effort
            # add effort for percent distance from entry point
            distance = distance_effort(x, y, board[:entry_x], board[:entry_y])
            # TODO: decrease effective distance if the semantic_id or clone_id:
            #       - are used on other boards in the set (semi)
            #         distance * 0.5 (* pct of matching boards) for semantic_id
            #         distance * 0.33 (* pct of matching boards) for clone_id
            #       - was also present on the prior board (total)
            #         distance * 0.5 for semantic_id
            #         distance * 0.33 for clone_id
            effort += distance
            if distance > DISTANCE_THRESHOLD_TO_SKIP_VISUAL_SCAN || (board[:entry_x] == 1.0 && board[:entry_y] == 1.0)
              # add small effort for every prior (visible) button when visually scanning
              visual_scan = visual_scan_effort(prior_buttons)
              effort += visual_scan
            else
              # ..unless it's right by the previous button, then
              # add tiny effort for local scan
              effort += distance * SKIPPED_VISUAL_SCAN_DISTANCE_MULTIPLIER
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
                    prior_effort: effort + BOARD_CHANGE_PROCESSING_EFFORT,
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
      reference_counts: refs,
      grid: {
        rows: root_rows,
        columns: root_cols
      },
      buttons: buttons,
      levels: clusters
    }
  end

  SQRT2 = Math.sqrt(2)
  BUTTON_SIZE_MULTIPLIER = 0.09
  FIELD_SIZE_MULTIPLIER = 0.017
  VISUAL_SCAN_MULTIPLIER = 0.02
  BOARD_CHANGE_PROCESSING_EFFORT = 1.0
  DISTANCE_MULTIPLIER = 0.5
  DISTANCE_THRESHOLD_TO_SKIP_VISUAL_SCAN = 0.1
  SKIPPED_VISUAL_SCAN_DISTANCE_MULTIPLIER = 0.5

  def self.button_size_effort(rows, cols)
    BUTTON_SIZE_MULTIPLIER * (rows + cols) / 2
  end

  def self.field_size_effort(button_count)
    FIELD_SIZE_MULTIPLIER * button_count
  end

  def self.visual_scan_effort(prior_buttons)
    prior_buttons * VISUAL_SCAN_MULTIPLIER
  end
  
  def self.distance_effort(x, y, entry_x, entry_y)
    Math.sqrt((x - entry_x) ** 2 + (y - entry_y) ** 2) / SQRT2 * DISTANCE_MULTIPLIER
  end

  def self.spelling_effort(word)
    10 + (word.length * 2.5)
  end

  def self.analyze_and_compare(obfset, compset)
    target = AACMetrics::Metrics.analyze(obfset, false)
    res = {}.merge(target)

    compare = AACMetrics::Metrics.analyze(compset, false)
    res[:comp_boards] = compare[:total_boards]
    res[:comp_buttons] = compare[:total_buttons]
    res[:comp_grid] = compare[:grid]
    
    compare_words = []
    compare_buttons = {}
    comp_efforts = {}
    comp_levels = {}
    compare[:buttons].each do |btn|
      compare_words << btn[:label]
      compare_buttons[btn[:label]] = btn
      comp_efforts[btn[:label]] = btn[:effort]
      comp_levels[btn[:label]] = btn[:level]
    end

    sortable_efforts = {}
    target_efforts = {}
    target_levels = {}
    target_words = []
    # Track effort scores for each button in the set,
    # used to sort and for assessing priority
    # TODO: keep a list of expected effort scores for
    # very frequent core words and use that when available
    res[:buttons].each{|b| 
      target_words << b[:label]
      target_efforts[b[:label]] = b[:effort]
      target_levels[b[:label]] = b[:level]
      sortable_efforts[b[:label]] = b[:effort] 
      comp = compare_buttons[b[:label]]
      if comp
        b[:comp_level] = comp[:level]
        b[:comp_effort] = comp[:effort]
      end
    }
    # Effort scores are the mean of thw scores from the
    # two sets, or just a singular value if in only one set
    compare[:buttons].each{|b| 
      if sortable_efforts[b[:label]]
        sortable_efforts[b[:label]] += b[:effort] 
        sortable_efforts[b[:label]] /= 2
      else
        sortable_efforts[b[:label]] ||= b[:effort] 
      end
    }
    
    core_lists = AACMetrics::Loader.core_lists(target[:locale])
    common_words_obj = AACMetrics::Loader.common_words(target[:locale])
    synonyms = AACMetrics::Loader.synonyms(target[:locale])
    sentences = AACMetrics::Loader.sentences(target[:locale])
    fringe = AACMetrics::Loader.fringe_words(target[:locale])
    common_words_obj['efforts'].each{|w, e| sortable_efforts[w] ||= e }
    common_words = common_words_obj['words']
    
    # Track which words are significantly harder or easier than expected
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

    
    missing = (compare_words - target_words).sort_by{|w| sortable_efforts[w] }
    missing = missing.select do |word|
      !synonyms[word] || (synonyms[word] & target_words).length == 0
    end
    extras = (target_words - compare_words).sort_by{|w| sortable_efforts[w] }
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
    target_effort_tally = 0.0
    comp_effort_tally = 0.0
    # For each core list, find any missing words, and compute
    # the average level of effort for all words in the set,
    # using a fallback effort metric if the word isn't in the
    # board set
    # puts missing.join('  ')
    core_lists.each do |list|
      missing = []
      comp_missing = []
      list_effort = 0
      comp_effort = 0
      list['words'].each do |word|
        words = [word] + (synonyms[word] || [])
        # Check if any words from the core list are missing in the set
        if (target_words & words).length == 0
          missing << word
        end
        if (compare_words & words).length == 0
          comp_missing << word
        end

        # Calculate the effort for the target and comp sets
        effort = target_efforts[word]
        if !effort
          words.each{|w| effort ||= target_efforts[w] }
        end
        # Fallback penalty for missing word
        effort ||= spelling_effort(word)
        list_effort += effort

        effort = comp_efforts[word]
        if !effort
          words.each{|w| effort ||= comp_efforts[w] }
        end
        effort ||= spelling_effort(word)
        comp_effort += effort
      end
      if missing.length > 0
        # puts "MISSING FROM #{list['id']} (#{missing.length}):"
        res[:missing][list['id']] = {name: list['name'], list: missing, average_effort: list_effort}
        # puts missing.join('  ')
      end
      list_effort = list_effort.to_f / list['words'].length.to_f
      comp_effort = comp_effort.to_f / list['words'].length.to_f
      target_effort_tally += list_effort
      comp_effort_tally += comp_effort
      res[:cores][list['id']] = {name: list['name'], list: list['words'], average_effort: list_effort, comp_effort: comp_effort}
    end
    target_effort_tally = (target_effort_tally / core_lists.to_a.length) * 5.0
    comp_effort_tally = (comp_effort_tally / core_lists.to_a.length) * 5.0

    # TODO: Assemble or allow a battery of word combinations,
    # and calculate the level of effort for each sequence,
    # as well as an average level of effort across combinations.
    res[:sentences] = []
    sentences.each do |words|
      target_effort_score = 0.0
      comp_effort_score = 0.0
      words.each_with_index do |word, idx|
        synonym_words = [word] + (synonyms[word] || [])
        effort = target_efforts[word] || target_efforts[word.downcase]
        level = target_levels[word] || target_levels[word.downcase]
        if !effort
          synonym_words.each do |w| 
            if !effort && target_efforts[w]
              effort = target_efforts[w]
              level = target_levels[w]
            end
          end
        end
        effort ||= spelling_effort(word)
        if level && level > 0 && idx > 0
          effort += BOARD_CHANGE_PROCESSING_EFFORT
        end
        ee = effort
        target_effort_score += effort

        effort = comp_efforts[word] || comp_efforts[word.downcase]
        level = comp_levels[word] || comp_levels[word.downcase]
        if !effort
          synonym_words.each do |w| 
            if !effort && comp_efforts[w]
              effort = comp_efforts[w]
              level = comp_levels[w]
            end
          end
        end
        effort ||= spelling_effort(word)
        if level && level > 0 && idx > 0
          effort += BOARD_CHANGE_PROCESSING_EFFORT
        end
        comp_effort_score += effort
      end
      target_effort_score = target_effort_score / words.length
      comp_effort_score = comp_effort_score / words.length
      res[:sentences] << {sentence: words.join(' '), words: words, effort: target_effort_score, comp_effort: comp_effort_score}
    end
    target_effort_tally += res[:sentences].map{|s| s[:effort] }.sum.to_f / res[:sentences].length.to_f * 3.0
    comp_effort_tally += res[:sentences].map{|s| s[:comp_effort] }.sum.to_f / res[:sentences].length.to_f * 3.0

    res[:fringe_words] = []
    fringe.each do |word|
      target_effort_score = 0.0
      comp_effort_score = 0.0
      synonym_words = [word] + (synonyms[word] || [])
      effort = target_efforts[word] || target_efforts[word.downcase]
      if !effort
        synonym_words.each{|w| effort ||= target_efforts[w] }
      end
      effort ||= spelling_effort(word)
      target_effort_score += effort

      effort = comp_efforts[word] || comp_efforts[word.downcase]
      if !effort
        synonym_words.each{|w| effort ||= comp_efforts[w] }
      end
      effort ||= spelling_effort(word)
      comp_effort_score += effort
      res[:fringe_words] << {word: word, effort: target_effort_score, comp_effort: comp_effort_score}
    end
    target_effort_tally += res[:fringe_words].map{|s| s[:effort] }.sum.to_f / res[:fringe_words].length.to_f * 2.0
    comp_effort_tally += res[:fringe_words].map{|s| s[:comp_effort] }.sum.to_f / res[:fringe_words].length.to_f * 2.0

    target_effort_tally += 80 # placeholder value for future added calculations
    comp_effort_tally += 80



    res[:target_effort_score] = target_effort_tally
    res[:comp_effort_score] = comp_effort_tally
    # puts "CONSIDER MAKING EASIER"
    res[:high_effort_words] = too_hard
    # puts too_hard.join('  ')
    # puts "CONSIDER LESS PRIORITY"
    res[:low_effort_words] = too_easy
    # puts too_easy.join('  ')
    res
  end
end