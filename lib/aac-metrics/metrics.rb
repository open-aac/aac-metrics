# TODO:
# Qualitative evaluation criteria:
# - this set looks easy to learn for communicators
# - this set looks easy to learn for supporters
# - this vocabulary organization of this set makes sense
# - this set provides clear locations for user-specific words to be added
# - this set supports the use of grammatical forms (tenses and other inflections)
# - this set provides predefined simplification for beginning communicators
# - this set allows for long-term vocabulary growth over time
# - this vocabulary looks like it will work well for young users
# - this vocabulary looks like it will work well for adult users

# Effort algorithms for scanning/eyes
module AACMetrics::Metrics
    # A. When navigating from one board to the next, grid locations
    # with the same clone_id or semantic_id should result in a
    # discount to overall search based more on the number of
    # uncloned/unsemantic buttons than the number of total buttons
    # (perhaps also factoring in the percent of board with that
    # id present in the full board set)
    # B. When selecting a button with a semantic_id or clone_id,
    # a discount to both search and selection should
    # be applied based on the percent of boards that
    # contain the same id at that grid location
    # C. When selecting a button with a semantic_id or clone_id,
    # if the same id was present on the previous board,
    # an additional discount to search and selection should be applied
    # D When selecting a button with a semantic_id or clone_id,
    # apply a steep discount to the button in the same location
    # as the link used to get there if they share an id
  def self.analyze(obfset, output=true, include_obfset=false)
    locale = nil
    buttons = []
    set_refs = {}
    grid = {}

    if obfset.is_a?(Hash) && obfset['buttons']
      locale = obfset['locale'] || 'en'
      set_refs = obfset['reference_counts']
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
      set_refs = {}
      cell_refs = {}
      rows_tally = 0.0
      cols_tally = 0.0
      root_rows = nil
      root_cols = nil
      # Gather repeated words/concepts
      obfset.each do |board|
        # try to figure out the average grid size for board set
        root_rows ||= board['grid']['rows']
        root_cols ||= board['grid']['columns']
        rows_tally += board['grid']['rows']
        cols_tally += board['grid']['columns']
        # determine frequency within the board set
        # for each semantic_id and clone_id
        if board['clone_ids']
          board['clone_ids'].each do |id|
            set_refs[id] ||= 0
            set_refs[id] += 1
          end
        end
        board['grid']['rows'].times do |row_idx|
          board['grid']['columns'].times do |col_idx|
            id = (board['grid']['order'][row_idx] || [])[col_idx]
            cell_refs["#{row_idx}.#{col_idx}"] ||= 0.0
            cell_refs["#{row_idx}.#{col_idx}"] += id ? 1.0 : 0.25
          end
        end
        if board['semantic_ids']
          board['semantic_ids'].each do |id|
            set_refs[id] ||= 0
            set_refs[id] += 1
          end
        end
      end
      # If the average grid size is much different than the root
      # grid size, only then use the average as the size for this board set
      if (rows_tally / obfset.length.to_f - root_rows).abs > 3 || (cols_tally / obfset.length.to_f - root_cols).abs > 3
        root_rows = (rows_tally / obfset.length.to_f).floor
        root_cols = (cols_tally / obfset.length.to_f).floor
      end
      set_pcts = {}
      set_refs.each do |id, cnt|
        loc = id.split(/-/)[1]
        set_pcts[id] = cnt.to_f / (cell_refs[loc] || obfset.length).to_f
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
        reuse_discount = 0.0
        board[:board]['grid']['rows'].times do |row_idx|
          board[:board]['grid']['columns'].times do |col_idx|
            button_id = (board[:board]['grid']['order'][row_idx] || [])[col_idx]
            button = board[:board]['buttons'].detect{|b| b['id'] == button_id }
            if button && button['clone_id'] && set_pcts[button['clone_id']]
              reuse_discount += REUSED_CLONE_FROM_OTHER_DISCOUNT * set_pcts[button['clone_id']]
            elsif button && button['semantic_id'] && set_pcts[button['semantic_id']]
              reuse_discount += REUSED_SEMANTIC_FROM_OTHER_DISCOUNT * set_pcts[button['semantic_id']]
            end
          end
        end
        board_effort -= reuse_discount
        prior_buttons = 0

        # Calculate the percent of links to this board
        # that had or were linked by clone_ids or semantic_ids
        board_pcts = {}
        obfset.each do |brd|
          brd['buttons'].each do |link_btn|
            #  For every board that links to this board
            if link_btn['load_board'] && link_btn['load_board']['id'] == board[:board]['id']
              board_pcts['all'] ||= 0
              board_pcts['all'] += 1
              # Count how many of those links have a clone_id or semantic_id
              if link_btn['clone_id']
                board_pcts[link_btn['clone_id']] ||= 0
                board_pcts[link_btn['clone_id']] += 1
              end
              if link_btn['semantic_id']
                board_pcts[link_btn['semantic_id']] ||= 0
                board_pcts[link_btn['semantic_id']] += 1
              end
              # Also count all the clone_ids and semantic_ids
              # anywhere on the boards that link to this one
              (brd['clone_ids'] || []).uniq.each do |cid|
                board_pcts["upstream-#{cid}"] ||= 0
                board_pcts["upstream-#{cid}"] += 1
              end
              (brd['semantic_ids'] || []).uniq.each do |sid|
                board_pcts["upstream-#{sid}"] ||= 0
                board_pcts["upstream-#{sid}"] += 1
              end
            end
          end
        end
        board_pcts.each do |id, cnt|
          board_pcts[id] = board_pcts[id].to_f / board_pcts['all'].to_f
        end

        board[:board]['grid']['rows'].times do |row_idx|
          board[:board]['grid']['columns'].times do |col_idx|
            button_id = (board[:board]['grid']['order'][row_idx] || [])[col_idx]
            button = board[:board]['buttons'].detect{|b| b['id'] == button_id }
            # prior_buttons += 0.1 if !button
            next unless button
            x = (btn_width / 2)  + (btn_width * col_idx)
            y = (btn_height / 2) + (btn_height * row_idx)
            # prior_buttons = (row_idx * board[:board]['grid']['columns']) + col_idx
            # calculate the percentage of links that point to this button
            # and match on semantic_id or clone_id
            effort = 0
            # Additional discount on board search effort,
            # remember that semantic_id and clone_id are 
            # keyed to the same grid location, so matches only
            # apply to that specific location
            #       - if this button's semantic_id or clone_id
            #         was also present anywhere on the prior board
            #         board_effort * 0.5 for semantic_id
            #         board_effort * 0.33 for clone_id
            #       - if this button's semantic_id or clone_id
            #         is directly used to navigate to this board
            #         board_effort * 0.1 for semantic_id
            #         board_effort * 0.1 for clone_id
            button_effort = board_effort
            if board_pcts[button['semantic_id']]
              # TODO: Pull out these magic numbers
              button_effort = [button_effort, button_effort * SAME_LOCATION_AS_PRIOR_DISCOUNT / board_pcts[button['semantic_id']]].min
            elsif board_pcts["upstream-#{button['semantic_id']}"]
              button_effort = [button_effort, button_effort * RECOGNIZABLE_SEMANTIC_FROM_PRIOR_DISCOUNT / board_pcts["upstream-#{button['semantic_id']}"]].min
            end
            if board_pcts[button['clone_id']]
              button_effort = [button_effort, button_effort * SAME_LOCATION_AS_PRIOR_DISCOUNT / board_pcts[button['clone_id']]].min
            elsif board_pcts["upstream-#{button['clone_id']}"]
              button_effort = [button_effort, button_effort * RECOGNIZABLE_CLONE_FROM_PRIOR_DISCOUNT / board_pcts["upstream-#{button['clone_id']}"]].min
            end
            effort += button_effort
            # add effort for percent distance from entry point
            distance = distance_effort(x, y, board[:entry_x], board[:entry_y])
            # TODO: decrease effective distance if the semantic_id or clone_id:
            #       - are used on other boards in the set (semi)
            #         distance * 0.5 (* pct of matching boards) for semantic_id
            #         distance * 0.33 (* pct of matching boards) for clone_id
            #       - was also present on the prior board (total)
            #         distance * 0.5 for semantic_id
            #         distance * 0.33 for clone_id
            #       - is directly used to navigate to this board
            #         distance * 0.1 * (pct of links that match) for semantic_id
            #         distance * 0.1 * (pct of links that match) for clone_id
            if board_pcts[button['semantic_id']]
              distance = [distance, distance * SAME_LOCATION_AS_PRIOR_DISCOUNT / board_pcts[button['semantic_id']]].min
            elsif board_pcts["upstream-#{button['semantic_id']}"]
              distance = [distance, distance * RECOGNIZABLE_SEMANTIC_FROM_PRIOR_DISCOUNT / board_pcts["upstream-#{button['semantic_id']}"]].min
            elsif set_pcts[button['semantic_id']]
              distance = [distance, distance * RECOGNIZABLE_SEMANTIC_FROM_OTHER_DISCOUNT / set_pcts[button['semantic_id']]].min
            end
            if board_pcts[button['clone_id']]
              distance = [distance, distance * SAME_LOCATION_AS_PRIOR_DISCOUNT / board_pcts[button['clone_id']]].min
            elsif board_pcts["upstream-#{button['clone_id']}"]
              distance = [distance, distance * RECOGNIZABLE_CLONE_FROM_PRIOR_DISCOUNT / board_pcts["upstream-#{button['clone_id']}"]].min
            elsif set_pcts[button['clone_id']]
              distance = [distance, distance * RECOGNIZABLE_CLONE_FROM_OTHER_DISCOUNT / set_pcts[button['clone_id']]].min
            end

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
                change_effort = BOARD_CHANGE_PROCESSING_EFFORT
                if next_board
                  to_visit.push({
                    board: next_board,
                    level: board[:level] + 1,
                    prior_effort: effort + change_effort,
                    entry_x: x,
                    entry_y: y,
                    entry_clone_id: button['clone_id'],
                    entry_semantic_id: button['semantic_id']
                  })
                end
              end
            else
              word = button['label']
              existing = known_buttons[word]
              if !existing || effort < existing[:effort] #board[:level] < existing[:level]
                if board_pcts[button['clone_id']]
                  effort -= [BOARD_CHANGE_PROCESSING_EFFORT, BOARD_CHANGE_PROCESSING_EFFORT * 0.3 / board_pcts[button['clone_id']]].min
                elsif board_pcts[button['semantic_id']]
                  effort -= [BOARD_CHANGE_PROCESSING_EFFORT, BOARD_CHANGE_PROCESSING_EFFORT * 0.5 / board_pcts[button['semantic_id']]].min
                end

                known_buttons[word] = {
                  id: "#{button['id']}::#{board[:board]['id']}",
                  label: word,
                  level: board[:level],
                  effort: effort,
                }
              end
            end
            button['effort'] = effort

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
    res = {
      analysis_version: AACMetrics::VERSION,
      locale: locale,
      total_boards: total_boards,
      total_buttons: buttons.length,
      reference_counts: set_refs,
      grid: {
        rows: root_rows,
        columns: root_cols
      },
      buttons: buttons,
      levels: clusters
    }
    if include_obfset
      res[:obfset] = obfset
    end
    res
  end

  SQRT2 = Math.sqrt(2)
  BUTTON_SIZE_MULTIPLIER = 0.09
  FIELD_SIZE_MULTIPLIER = 0.005
  VISUAL_SCAN_MULTIPLIER = 0.015
  BOARD_CHANGE_PROCESSING_EFFORT = 1.0
  DISTANCE_MULTIPLIER = 0.4
  DISTANCE_THRESHOLD_TO_SKIP_VISUAL_SCAN = 0.1
  SKIPPED_VISUAL_SCAN_DISTANCE_MULTIPLIER = 0.5
  SAME_LOCATION_AS_PRIOR_DISCOUNT = 0.1
  RECOGNIZABLE_SEMANTIC_FROM_PRIOR_DISCOUNT = 0.5
  RECOGNIZABLE_SEMANTIC_FROM_OTHER_DISCOUNT = 0.6
  RECOGNIZABLE_CLONE_FROM_PRIOR_DISCOUNT = 0.33
  RECOGNIZABLE_CLONE_FROM_OTHER_DISCOUNT = 0.4
  REUSED_SEMANTIC_FROM_OTHER_DISCOUNT = 0.0025
  REUSED_CLONE_FROM_OTHER_DISCOUNT = 0.005

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

  def self.analyze_and_compare(obfset, compset, include_obfset=false)
    target = AACMetrics::Metrics.analyze(obfset, false, include_obfset)
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
    common_fringe = AACMetrics::Loader.common_fringe_words(target[:locale])
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

    res[:common_fringe_words] = []
    common_fringe.each do |word|
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
      res[:common_fringe_words] << {word: word, effort: target_effort_score, comp_effort: comp_effort_score}
    end
    target_effort_tally += res[:common_fringe_words].map{|s| s[:effort] }.sum.to_f / res[:common_fringe_words].length.to_f * 1.0
    comp_effort_tally += res[:common_fringe_words].map{|s| s[:comp_effort] }.sum.to_f / res[:common_fringe_words].length.to_f * 1.0

    target_effort_tally += 70 # placeholder value for future added calculations
    comp_effort_tally += 70



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