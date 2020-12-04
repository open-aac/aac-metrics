require 'json'
require 'typhoeus'
require 'digest'
require 'aac-metrics'

fn = ARGV[0]
token = ARGV[1]
puts AACMetrics::Loader.ingest(fn, token)
