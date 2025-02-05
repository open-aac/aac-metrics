# TODO:
# Qualitative evaluation criteria:
# - this set provides clear locations for user-specific words to be added
# - this set supports the use of grammatical forms (tenses and other inflections)
# - this set provides predefined simplification for beginning communicators

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
    buttons = nil
    set_refs = {}
    grid = {}
    alt_scores = {}

    if obfset.is_a?(Hash) && obfset['buttons']
      locale = obfset['locale'] || 'en'
      set_refs = obfset['reference_counts']
      grid = obfset['grid']
      alt_scores = obfset['alternates']
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
      start_boards = [obfset[0]]
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
        board['buttons'].each do |link_btn|
          if link_btn['load_board'] && link_btn['load_board']['id'] && link_btn['load_board']['temporary_home']
            # TODO: buttons can have multiple efforts, depending
            # on if they are navigable from a temporary_home
            if link_btn['load_board']['temporary_home'] == 'prior'
              start_boards << board
            elsif link_btn['load_board']['temporary_home'] == true
              start_boards << obfset.detect{|b| b['id'] == link_btn['load_board']['id']}
            end
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

      total_boards = nil
      locale = nil
      clusters = nil
      # TODO: this list used to be reversed, but I don't know why.
      # What we want is for these analyses to be run for the root
      # board, don't we?
      # puts JSON.pretty_generate(obfset[0])
      start_boards.uniq.each do |brd|
        analysis = analyze_for(obfset, brd, set_pcts, output)
        buttons ||= analysis[:buttons]
        if brd != obfset[0]
          alt_scores[brd['id']] = {
            buttons: analysis[:buttons],
            levels: analysis[:levels]
          }
        end
        total_boards ||= analysis[:total_boards]
        clusters ||= analysis[:levels]
        locale ||= analysis[:locale]
      end
    end
    res = {
      analysis_version: AACMetrics::VERSION,
      locale: locale,
      total_boards: total_boards,
      total_buttons: buttons.map{|b| b[:count] || 1}.sum,
      total_words: buttons.map{|b| b[:label] }.uniq.length,
      reference_counts: set_refs,
      grid: {
        rows: root_rows,
        columns: root_cols
      },
      buttons: buttons,
      levels: clusters,
      alternates: alt_scores
    }
    if include_obfset
      res[:obfset] = obfset
    end
    res
  end

  def self.analyze_for(obfset, brd, set_pcts, output)
      visited_board_ids = {}
      to_visit = [{board: brd, level: 0, entry_x: 1.0, entry_y: 1.0}]
      locale = brd['locale'] || 'en'
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
              reuse_discount += REUSED_CLONE_FROM_OTHER_BONUS * set_pcts[button['clone_id']]
            elsif button && button['semantic_id'] && set_pcts[button['semantic_id']]
              reuse_discount += REUSED_SEMANTIC_FROM_OTHER_BONUS * set_pcts[button['semantic_id']]
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
            next unless button && (button['label'] || button['vocalization'] || '').length > 0
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
              prior = button_effort
              button_effort = [button_effort, button_effort * SAME_LOCATION_AS_PRIOR_DISCOUNT / board_pcts[button['semantic_id']]].min
#              puts "  #{button['label']} #{prior.round(1)} - #{prior - button_effort}"
            elsif board_pcts["upstream-#{button['semantic_id']}"]
              prior = button_effort
              button_effort = [button_effort, button_effort * RECOGNIZABLE_SEMANTIC_FROM_PRIOR_DISCOUNT / board_pcts["upstream-#{button['semantic_id']}"]].min
              # puts "  #{button['label']} #{prior.round(1)} - #{prior - button_effort}"
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

            # TODO: If any board links are sticky, or if
            # the board set isn't auto-home, or any board links
            # are add_to_sentence, then the logic will be different
            # for calculating effort scores, since the route matters
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
                  temp_home_id = board[:temporary_home_id]
                  temp_home_id = board[:board]['id'] if button['load_board']['temporary_home'] == 'prior'
                  temp_home_id = button['load_board']['id'] if button['load_board']['temporary_home'] == true
                  to_visit.push({
                    board: next_board,
                    level: board[:level] + 1,
                    prior_effort: effort + change_effort,
                    temporary_home_id: temp_home_id,
                    entry_x: x,
                    entry_y: y,
                    entry_clone_id: button['clone_id'],
                    entry_semantic_id: button['semantic_id']
                  })
                end
              end
            end
            if !button['load_board'] || button['load_board']['add_to_sentence']
              word = button['label']
              existing = known_buttons[word]
              if board_pcts[button['clone_id']]
                effort -= [BOARD_CHANGE_PROCESSING_EFFORT, BOARD_CHANGE_PROCESSING_EFFORT * 0.3 / board_pcts[button['clone_id']]].min
              elsif board_pcts[button['semantic_id']]
                effort -= [BOARD_CHANGE_PROCESSING_EFFORT, BOARD_CHANGE_PROCESSING_EFFORT * 0.5 / board_pcts[button['semantic_id']]].min
              end
              if !existing || effort < existing[:effort]
                ww = {
                  id: "#{button['id']}::#{board[:board]['id']}",
                  label: word,
                  level: board[:level],
                  effort: effort,
                  count: ((existing || {})[:count] || 0) + 1
                }
                # If a board set has any temporary_home links,
                # then that can possibly affect the effort
                # score for sentences
                if board[:temporary_home_id]
                  ww[:temporary_home_id] = board[:temporary_home_id]
                end
                known_buttons[word] = ww
              end
            end
            button['effort'] = effort
          end
        end
      end # end to_visit list
      buttons = known_buttons.to_a.map(&:last)
      total_boards = visited_board_ids.keys.length

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
      buttons: buttons,
      levels: clusters
    }
    res
  end

  class ExtraFloat < Numeric
    include Math
    def initialize(float=0.0)
      @float = Float(float)
    end
  
    def to_f
      @float.to_f
    end

    def method_missing(message, *args, &block)
      if block_given?
        @float.public_send(message, *args, &block)
      else
        @float.public_send(message, *args)
      end
    end
  end

  SQRT2 = Math.sqrt(2)
  BUTTON_SIZE_MULTIPLIER = 0.09
  FIELD_SIZE_MULTIPLIER = 0.005
  VISUAL_SCAN_MULTIPLIER = 0.015
  BOARD_CHANGE_PROCESSING_EFFORT = 1.0
  BOARD_HOME_EFFORT = 1.0
  COMBINED_WORDS_REMEMBERING_EFFORT = 1.0
  DISTANCE_MULTIPLIER = 0.4
  DISTANCE_THRESHOLD_TO_SKIP_VISUAL_SCAN = 0.1
  SKIPPED_VISUAL_SCAN_DISTANCE_MULTIPLIER = 0.5
  SAME_LOCATION_AS_PRIOR_DISCOUNT = 0.1
  RECOGNIZABLE_SEMANTIC_FROM_PRIOR_DISCOUNT = 0.5
  RECOGNIZABLE_SEMANTIC_FROM_OTHER_DISCOUNT = 0.5
  REUSED_SEMANTIC_FROM_OTHER_BONUS = 0.0025
  RECOGNIZABLE_CLONE_FROM_PRIOR_DISCOUNT = 0.33
  RECOGNIZABLE_CLONE_FROM_OTHER_DISCOUNT = 0.33
  REUSED_CLONE_FROM_OTHER_BONUS = 0.005

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
    res[:comp_words] = compare[:total_words]
    res[:comp_grid] = compare[:grid]
    
    compare_words = []
    compare_buttons = {}
    comp_efforts = {}
    comp_levels = {}
    compare[:buttons].each do |btn|
      compare_words << btn[:label]
      compare_buttons[btn[:label]] = btn
      comp_efforts[btn[:label]] = ExtraFloat.new(btn[:effort])
      comp_efforts[btn[:label]].instance_variable_set('@temp_home_id', btn[:temporary_home_id])
      comp_levels[btn[:label]] = btn[:level]
    end
    compare[:alternates].each do |id, alt|
      efforts = {}
      levels = {}
      alt[:buttons].each do |btn|
        efforts[btn[:label]] = ExtraFloat.new(btn[:effort])
        efforts[btn[:label]].instance_variable_set('@temp_home_id', btn[:temporary_home_id])
        levels[btn[:label]] = btn[:level]
      end
      comp_efforts["H:#{id}"] = efforts
      comp_levels["H:#{id}"] = levels
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
      target_efforts[b[:label]] = ExtraFloat.new(b[:effort])
      target_efforts[b[:label]].instance_variable_set('@temp_home_id', b[:temporary_home_id])

      target_levels[b[:label]] = b[:level]
      sortable_efforts[b[:label]] = b[:effort] 
      comp = compare_buttons[b[:label]]
      if comp
        b[:comp_level] = comp[:level]
        b[:comp_effort] = comp[:effort]
      end
    }
    res[:alternates].each do |id, alt|
      efforts = {}
      levels = {}
      alt[:buttons].each do |btn|
        efforts[btn[:label]] = ExtraFloat.new(btn[:effort])
        efforts[btn[:label]].instance_variable_set('@temp_home_id', btn[:temporary_home_id])
        levels[btn[:label]] = btn[:level]
      end
      target_efforts["H:#{id}"] = efforts
      target_levels["H:#{id}"] = levels
    end
    res.delete(:alternates)
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
    res[:care_components] = {}
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
        effort, level, fallback = best_match(word, target_efforts, nil, synonyms)
        reffort = effort
        list_effort += effort

        effort, level, fallback = best_match(word, comp_efforts, nil, synonyms)
        comp_effort += effort
        # puts "#{word} - #{reffort.round(1)} - #{effort.round(1)}"
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
    res[:care_components][:core] = (target_effort_tally / core_lists.to_a.length) * 5.0
    target_effort_tally = res[:care_components][:core]
    res[:care_components][:comp_core] = (comp_effort_tally / core_lists.to_a.length) * 5.0
    comp_effort_tally = res[:care_components][:comp_core]

    # Assemble or allow a battery of word combinations,
    # and calculate the level of effort for each sequence,
    # as well as an average level of effort across combinations.
    # TODO: sets with temporary_home settings will have custom
    # effort scores for subsequent words in the sentence
    res[:sentences] = []
    sentences.each do |words|
      sequence = best_combo(words, target_efforts, target_levels, synonyms)
      target_effort_score = sequence[:list].map{|w, e| e }.sum.to_f / words.length.to_f
      typing = sequence[:fallback]
      sequence = best_combo(words, comp_efforts, comp_levels, synonyms)
      comp_effort_score = sequence[:list].map{|w, e| e }.sum.to_f / words.length.to_f
      comp_typing = sequence[:fallback]

      res[:sentences] << {sentence: words.join(' '), words: words, effort: target_effort_score, typing: typing, comp_effort: comp_effort_score, comp_typing: comp_typing}
    end
    res[:care_components][:sentences] = res[:sentences].map{|s| s[:effort] }.sum.to_f / res[:sentences].length.to_f * 3.0
    target_effort_tally += res[:care_components][:sentences]
    res[:care_components][:comp_sentences] = res[:sentences].map{|s| s[:comp_effort] }.sum.to_f / res[:sentences].length.to_f * 3.0
    comp_effort_tally += res[:care_components][:comp_sentences]

    res[:fringe_words] = []
    res[:missing]['fringe'] = {name: "Fringe Large Possible Corpus", list: []}
    fringe.each do |word|
      target_effort_score = 0.0
      comp_effort_score = 0.0

      effort, level, fallback = best_match(word, target_efforts, nil, synonyms)
      target_effort_score += effort
      res[:missing]['fringe'][:list] << word if fallback

      effort, level, fallback = best_match(word, comp_efforts, nil, synonyms)
      comp_effort_score += effort
      res[:fringe_words] << {word: word, effort: target_effort_score, comp_effort: comp_effort_score}
    end
    res[:care_components][:fringe] = res[:fringe_words].map{|s| s[:effort] }.sum.to_f / res[:fringe_words].length.to_f * 2.0
    target_effort_tally += res[:care_components][:fringe]
    res[:care_components][:comp_fringe] = res[:fringe_words].map{|s| s[:comp_effort] }.sum.to_f / res[:fringe_words].length.to_f * 2.0
    comp_effort_tally += res[:care_components][:comp_fringe]

    res[:common_fringe_words] = []
    res[:missing]['common_fringe'] = {name: "High-Use Fringe Corpus", list: []}
    common_fringe.each do |word|
      target_effort_score = 0.0
      comp_effort_score = 0.0
      effort, level, fallback = best_match(word, target_efforts, nil, synonyms)
      target_effort_score += effort
      res[:missing]['common_fringe'][:list] << word if fallback

      effort, level, fallback = best_match(word, comp_efforts, nil, synonyms)
      comp_effort_score += effort
      res[:common_fringe_words] << {word: word, effort: target_effort_score, comp_effort: comp_effort_score}
    end
    res[:care_components][:common_fringe] = res[:common_fringe_words].map{|s| s[:effort] }.sum.to_f / res[:common_fringe_words].length.to_f * 1.0
    target_effort_tally += res[:care_components][:common_fringe]
    res[:care_components][:comp_common_fringe] = res[:common_fringe_words].map{|s| s[:comp_effort] }.sum.to_f / res[:common_fringe_words].length.to_f * 1.0
    comp_effort_tally += res[:care_components][:comp_common_fringe]

    target_effort_tally += 70 # placeholder value for future added calculations
    comp_effort_tally += 70

    res[:target_effort_score] = [0.0, 350.0 - target_effort_tally].max
    res[:comp_effort_score] = [0.0, 350.0 - comp_effort_tally].max
    # puts "CONSIDER MAKING EASIER"
    res[:high_effort_words] = too_hard
    # puts too_hard.join('  ')
    # puts "CONSIDER LESS PRIORITY"
    res[:low_effort_words] = too_easy
    # puts too_easy.join('  ')
    res
  end

  # Find the effort for a word, its synonyms, or its spelling.
  # Always returns a non-nil effort score
  def self.best_match(word, target_efforts, target_levels, synonyms)
    synonym_words = [word] + (synonyms[word] || [])
    effort = target_efforts[word] || target_efforts[word.downcase]
    target_levels ||= {}
    level = target_levels[word] || target_levels[word.downcase]
    if !effort
      synonym_words.each do |w| 
        if !effort && target_efforts[w]
          effort = target_efforts[w]
          level = target_levels[w]
        end
      end
    end
    used_fallback = false

    # Fallback penalty for missing word
    fallback_effort = spelling_effort(word)
    if !effort || fallback_effort < effort
      used_fallback = true
      effort = fallback_effort 
    end

    [effort, level || 0, used_fallback]
  end

  def self.best_combo(words, efforts, levels, synonyms)
    options = [{next_idx: 0, list: []}]
    words.length.times do |idx|
      options.each do |option|
        home_id = option[:temporary_home_id]
        if option[:next_idx] == idx
          combos = forward_combos(words, idx, efforts, levels)
          if home_id
            # Effort of hitting home button, and processing change, plus usual
            combos.each{|c| c[:effort] += BOARD_HOME_EFFORT + BOARD_CHANGE_PROCESSING_EFFORT}
            more_combos = forward_combos(words, idx, efforts["H:#{home_id}"] || {}, levels["H:#{home_id}"] || {})
            more_combos.each{|c| c[:temporary_home_id] ||= home_id }
            combos += more_combos
          end
          combos.each do |combo|
            if idx > 0 && combo[:level] && combo[:level] > 0
              combo[:effort] += BOARD_CHANGE_PROCESSING_EFFORT
            end
            options << {
              next_idx: idx + combo[:size],
              list: option[:list] + [[combo[:partial], combo[:effort]]],
              temporary_home_id: combo[:temporary_home_id],
              fallback: option[:fallback]
            }
          end
          effort, level, fallback = best_match(words[idx], efforts, levels, synonyms)
          option[:temporary_home_id] = effort.instance_variable_get('@temp_home_id')
          option[:fallback] = true if fallback
          effort += BOARD_CHANGE_PROCESSING_EFFORT if idx > 0 && level && level > 0
          if home_id
            effort += BOARD_HOME_EFFORT + BOARD_CHANGE_PROCESSING_EFFORT
            other_effort, other_level, other_fallback = best_match(words[idx], efforts["H:#{home_id}"] || {}, levels["H:#{home_id}"] || {}, synonyms)
            new_home_id = other_effort.instance_variable_get('@temp_home_id') || home_id
            other_effort += BOARD_CHANGE_PROCESSING_EFFORT if idx > 0 && other_level && other_level > 0
            other_list = option[:list] + [[words[idx], other_effort]]
            options << {next_idx: idx + 1, list: other_list, temporary_home_id: new_home_id, fallback: option[:fallback] || other_fallback}
          end
          option[:list] << [words[idx], effort]
          option[:next_idx] = idx + 1
        end
      end
    end
    options.sort_by{|o| o[:list].map{|w, e| e}.sum }.reverse[0]
  end

  # Checks if any buttons will work for multiple words in a sentence
  def self.forward_combos(words, idx, target_efforts, target_levels)
    words_left = words.length - idx
    combos = []
    skip = 0
    temp_home_id = nil
    if words_left > 1
      (words_left - 1).times do |minus|
        partial = words[idx, words_left - minus].join(' ')
        if target_efforts[partial] || target_efforts[partial.downcase]
          effort = (target_efforts[partial] || target_efforts[partial.downcase]) + COMBINED_WORDS_REMEMBERING_EFFORT
          level = target_levels[partial] || target_levels[partial.downcase]
          combos << {
            partial: partial,
            effort: effort, 
            temporary_home_id: effort.instance_variable_get('@temp_home_id'),
            level: level, 
            size: words_left - minus
          }
        end
      end
    end
    combos
  end
end