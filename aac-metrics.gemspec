Gem::Specification.new do |s|
  s.name        = 'aac-metrics'

  s.add_dependency 'json'
  s.add_dependency 'typhoeus'

  s.add_development_dependency 'rspec'
  s.add_development_dependency 'ruby-debug'

  s.version     = '0.0.9'
  s.date        = '2020-12-08'
  s.summary     = "AAC Board Set Metrics"
  s.extra_rdoc_files = %W(LICENSE)
  s.description = "A tool for analysing and comparing grid-based AAC board sets"
  s.authors     = ["Brian Whitmer"]
  s.email       = 'brian.whitmer@gmail.com'

	s.files = Dir["{lib}/**/*"] + Dir["{sets}/**/*"] + ["LICENSE", "README.md"]
  s.require_paths = %W(lib)

  s.homepage    = 'https://github.com/open-aac/aac-metrics'
  s.license     = 'MIT'
end
