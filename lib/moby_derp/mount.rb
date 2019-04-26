module MobyDerp
	class Mount
		attr_reader :source, :target, :readonly

		def initialize(source:, target:, readonly: false)
			@source, @target, @readonly = source, target, readonly

			validate_source
			validate_target
			validate_readonly
		end

		private

		def validate_source
			unless @source.is_a?(String)
				raise ConfigurationError,
				      "mount source must be a string (got #{@source.inspect})"
			end

			if @source =~ %r{(^|/)\.\.($|/)}
				raise ConfigurationError,
				      "path traversal detected -- nice try, buddy"
			end

			if @source =~ %r{^(/|~)}
				raise ConfigurationError,
				      "mount sources can only be relative paths"
			end
		end

		def validate_target
			unless @target.is_a?(String)
				raise ConfigurationError,
				      "mount target must be a string (got #{@target.inspect})"
			end

			if @target =~ %r{(^|/)\.\.($|/)}
				raise ConfigurationError,
				      "target path must not contain '../'"
			end

			if @target !~ %r{^/}
				raise ConfigurationError,
				      "mount target must be an absolute path"
			end
		end

		def validate_readonly
			unless @readonly == true || @readonly == false
				raise ConfigurationError,
				      "readonly flag must be either true or false (got #{@readonly.inspect})"
			end
		end
	end
end
