require_relative "./error"
require_relative "./logging_helpers"

require "yaml"

module MobyDerp
	class ConfigFile
		include LoggingHelpers

		attr_reader :logger

		def initialize(filename)
			begin
				@logger.debug(logloc) { "Reading configuration file #{filename}" }
				@config = YAML.safe_load(File.read(filename))
			rescue Errno::ENOENT
				raise ConfigurationError,
				      "file does not exist"
			rescue Errno::EPERM
				raise ConfigurationError,
				      "cannot read file"
			rescue Psych::SyntaxError => ex
				raise ConfigurationError,
				      "invalid YAML syntax: #{ex.message}"
			end

			unless @config.is_a?(Hash)
				raise ConfigurationError,
				      "invalid file contents -- must be a map"
			end
		end
	end
end
