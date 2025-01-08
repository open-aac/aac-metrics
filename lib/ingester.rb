# Imports an obf dataset for future access.

lib_dir = File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(lib_dir) unless $LOAD_PATH.include?(lib_dir)

require 'json'
require 'typhoeus'
require 'digest'
require 'aac-metrics'

fn = ARGV[0]
token = ARGV[1]
puts AACMetrics::Loader.ingest(fn, token)
