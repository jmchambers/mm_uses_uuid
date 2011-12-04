# -*- encoding: utf-8 -*-
require File.expand_path('../lib/mm_uses_uuid/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Jonathan Chambers"]
  gem.email         = ["j.chambers@gmx.net"]
  gem.description   = %q{MongoMapper plugin that uses a UUID instead of the default ObjectID}
  gem.summary       = %q{UUIDs for MM}
  gem.homepage      = ''

  gem.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.files         = `git ls-files`.split("\n")
  gem.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.name          = "mm_uses_uuid"
  gem.require_paths = ['lib']
  gem.version       = MmUsesUuid::VERSION
  
  gem.add_development_dependency "rspec", "~> 2.7"
  gem.add_dependency "mongo_mapper", "~> 0.10.1"
  gem.add_dependency "bson_ext"#, "~> 1.5.0"

  
end
