require "spec"

ENV["OMNIVORE_SPEC"] = "true"

require "../src/omnivore-http"

# Keep logger silent by default
unless(ENV["DEBUG"]?)
  Omnivore.configure_logger({"log_path" => "/dev/null"} of String => String, {} of String => String)
else
  Omnivore.logger.level = Logger::DEBUG
end

macro generate_omnivore_config(config_name)
  Omnivore::Configuration.new(File.expand_path("spec/configs/{{config_name.id}}.json", Dir.current))
end

macro generate_omnivore_app(config_name)
  config = generate_omnivore_config({{config_name}})
  Omnivore::Application.new(config)
end
