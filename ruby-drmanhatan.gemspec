Gem::Specification.new do |spec|
  spec.name = "ruby-drmanhatan"
  spec.version = "0.1.1"
  spec.authors = ["AnimaLab"]
  spec.email = ["animalab.desenvolvimento@gmail.com"]

  spec.summary = "Observable event runtime for Ruby applications without telemetry vendor coupling."
  spec.description = "Semantic event runtime for Ruby workloads with neutral event publication, enrichers, and protocol session tracking."
  spec.homepage = "https://github.com/animalab-netizen/ruby-drmanhatan"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/animalab-netizen/ruby-drmanhatan",
    "changelog_uri" => "https://github.com/animalab-netizen/ruby-drmanhatan",
    "bug_tracker_uri" => "https://github.com/animalab-netizen/ruby-drmanhatan/issues"
  }

  spec.files = Dir[
    "lib/**/*.rb",
    "README.md"
  ]
  spec.require_paths = ["lib"]
end
