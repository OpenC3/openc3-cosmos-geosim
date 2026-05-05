# encoding: ascii-8bit

# Create the overall gemspec
spec = Gem::Specification.new do |s|
  s.name = 'openc3-cosmos-geosim'
  s.summary = 'OpenC3 cosmos-geosim plugin'
  s.description = <<-EOF
    cosmos-geosim plugin facilitating COSMOS config training
  EOF
  s.licenses = ['OpenC3']
  s.authors = ['OpenC3, Inc.']
  s.email = ['plugins@openc3.com']
  s.homepage = 'https://github.com/OpenC3/cosmos'
  s.platform = Gem::Platform::RUBY

  time = Time.now.strftime("%Y%m%d%H%M%S")
  if ENV['VERSION']
    s.version = ENV['VERSION'].dup
  else
    time = Time.now.strftime("%Y%m%d%H%M%S")
    s.version = '0.0.0' + ".#{time}"
  end
  s.files = Dir.glob("{targets,lib,public,tools,microservices}/**/*") + %w(Rakefile LICENSE.md README.md plugin.txt)

  s.metadata = {
    "source_code_uri" => "https://github.com/OpenC3/openc3-cosmos-geosim",
    "openc3_store_title" => "Geosim",
    "openc3_store_description" => "Geosim plugin facilitating COSMOS user training",
    "openc3_store_keywords" => "training",
  }
end
