Gem::Specification.new do |s|
  s.name        = 'aac-metrics'

  s.add_dependency 'json'
  s.add_dependency 'obf'

  s.add_development_dependency 'rspec'
  s.add_development_dependency 'ruby-debug'

  s.version     = '0.0.1'
  s.date        = '2020-12-02'
  s.summary     = "AAC Board Set Metrics"
  s.extra_rdoc_files = %W(LICENSE)
  s.description = "A tool for analysing and comparing grid-based AAC board sets"
  s.authors     = ["Brian Whitmer"]
  s.email       = 'brian.whitmer@gmail.com'

	s.files = Dir["{lib}/**/*"] + ["LICENSE", "README.md"]
  s.require_paths = %W(lib)

  s.homepage    = 'https://github.com/open-aac/aac-metrics'
  s.license     = 'MIT'
end