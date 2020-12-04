module AACMetrics::Metrics
  def self.analyze(obfset, output=true)
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
          # add small effort for every prior button when visually scanning
          effort += prior_buttons * 0.05
          # add effort for percent distance from entry point
          effort += Math.sqrt((x - board[:entry_x]) ** 2 + (y - board[:entry_y]) ** 2) / sqrt2
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
    buttons = known_buttons.to_a.map(&:last).sort_by{|b| b[:effort] }
    clusters = {}
    buttons.each do |btn| 
      puts "#{btn[:label]}\t#{btn[:effort]}" if output
      clusters[btn[:level]] ||= []
      clusters[btn[:level]] << btn
    end
    clusters.each do |level, buttons|
      puts "HITS: #{level + 1}" if output
      puts buttons.map{|b| b[:label] }.join('  ') if output
    end
    puts "TOTAL BOARDS: #{visited_board_ids.keys.length}" if output
    puts "TOTAL WORDS: #{buttons.length}" if output
    {
      locale: locale,
      buttons: buttons,
      levels: clusters
    }
  end
end