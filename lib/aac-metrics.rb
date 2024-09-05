# == What do we Want to Know?
# What words are available?
# What words are missing compared to other sets?
# Do we have words in the right locations based on their frequency?
# Is this a robust vocabulary?
# What words are availble in specific categories (cooking, tools, outdoor play, whatever)
# Is this vocabulary targeted at a specific age range?
# Are grammar inflections available?
# Does this support auto-home, or other motor planning supports?
# Are other language options available?
# How is the vocabulary organized?
# What platforms are supported?
# Access to keyboard w/ prediction? Numbers?
# How easy is it to say these personalized sentences: _____


# == Designer Sanity Checks
# What words/phrases am I forgetting?
# How many words did I end up with?
# Am I missing words from other vocabs?
# Are there related words I should consider adding to clusters?


# == Metric Factors
# number of visible buttons (more means more discrimination)
# distance from entry point (assume bottom-right for root)
# distance/wait time for row/col-based scanning
# number of alternatives to scan first (ltr/rtl, top-down)
# levels deep to access (more means more to remember/more focus time)
# visual clustering of like words/colors?

# == Metrics to Consider
# all words sorted by ease of access
# missing core words
# level of effort vs. expected for frequent core
# level of effort for test sentences
# spots to add personalized vocabulary
# average number of hits per word
# how many words can I hit with X button presses?
# total words
# visual clustering
# average hits to access by category, core vs. fringe
# thing explainer phrases, lists of words

module AACMetrics
  VERSION = "0.2"
  require 'aac-metrics/loader'
  require 'aac-metrics/metrics'
end