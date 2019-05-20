require_relative "./config_file"
require_relative "./container_config"
require_relative "./logging_helpers"
require_relative "./mount"

require "safe_yaml"
require "socket"

module MobyDerp
	class PodConfig < ConfigFile
		include LoggingHelpers

		attr_reader :name,
		            :containers,
		            :hostname,
		            :common_environment,
		            :common_labels,
		            :root_labels,
		            :common_mounts,
		            :expose,
		            :publish,
		            :publish_all,
		            :mount_root,
		            :system_config,
		            :logger

		def initialize(filename, system_config)
			@logger = system_config.logger

			super(filename)

			@system_config = system_config

			@name = File.basename(filename, ".*")
			validate_name


			unless @config.has_key?("containers")
				raise ConfigurationError,
				      "no containers defined"
			end
			@containers = @config.fetch("containers")
			validate_containers

			@logger.debug(logloc) { "Hostname is #{Socket.gethostname}" }
			@hostname = @config.fetch("hostname", "#{@name.gsub("_", "-")}-#{Socket.gethostname}")

			@common_environment = @config.fetch("common_environment", {})
			@common_labels      = @config.fetch("common_labels", {})
			@root_labels        = @config.fetch("root_labels", {})
			validate_common_environment
			validate_hash(:common_labels)
			validate_hash(:root_labels)

			@common_mounts = @config.fetch("common_mounts", [])
			@expose        = @config.fetch("expose", [])
			@publish       = @config.fetch("publish", [])

			if @system_config.use_host_resolv_conf
				@common_mounts << {
					"source"   => "/etc/resolv.conf",
					"target"   => "/etc/resolv.conf",
					"readonly" => true
				}
			end

			validate_common_mounts
			validate_expose
			validate_publish

			@publish_all = @config.fetch("publish_all", false)
			validate_publish_all

			@mount_root = File.join(system_config.mount_root, @name)
		end

		def network_name
			@system_config.network_name
		end

		private

		def validate_name
			@logger.debug(logloc) { "@name: #{@name.inspect}" }
			unless @name =~ /\A[A-Za-z0-9][A-Za-z0-9_-]*\z/
				raise ConfigurationError,
				      "pod name is invalid (must start with an alphanumeric character, and only contain alphanumerics, underscores, and hyphens)"
			end
		end

		def validate_containers
			@logger.debug(logloc) { "@containers: #{@containers.inspect}" }
			unless @containers.is_a?(Hash)
				raise ConfigurationError,
				      "containers must be a map of container names and container data"
			end

			@containers.each do |name, data|
				unless name =~ /\A[A-Za-z0-9_-]+\z/
					raise ConfigurationError,
						"container name #{name.inspect} is invalid (must contain only alphanumerics, underscores, and hyphens)"
				end
			end

			begin
				@containers = @containers.map { |k, v| ContainerConfig.new(system_config: @system_config, pod_config: self, container_name: k, **symbolize_keys(v)) }
			rescue ArgumentError => ex
				case ex.message
				when /unknown keywords?: (.*)$/
					raise ConfigurationError,
						   "unknown mount option(s): #{$1}"
				when /missing keywords?: (.*)$/
					raise ConfigurationError,
					      "missing mount option(s): #{$1}"
				else
					#:nocov:
					raise
					#:nocov:
				end
			end
		end

		def validate_common_environment
			validate_hash(:common_environment)

			if (bad_vars = @common_environment.keys.select { |k| k =~ /=/ }) != []
				raise ConfigurationError,
				      "environment variable names cannot include equals signs: #{bad_vars.inspect}"
			end
		end

		def validate_hash(name)
			h = instance_variable_get(:"@#{name}")
			@logger.debug(logloc) { "@#{name}: #{h.inspect}" }

			unless h.is_a?(Hash)
				raise ConfigurationError,
				      "#{h} is not a map"
			end

			unless (bad_keys = h.keys.select { |k| !k.is_a?(String) }) == []
				raise ConfigurationError,
				      "#{h} contains non-string key(s): #{bad_keys.inspect}"
			end

			unless (bad_values = h.values.select { |v| !v.is_a?(String) }) == []
				raise ConfigurationError,
				      "#{h} contains non-string value(s): #{bad_values.inspect}"
			end
		end

		def validate_common_mounts
			@logger.debug(logloc) { "@common_mounts: #{@common_mounts.inspect}" }
			unless @common_mounts.is_a?(Array)
				raise ConfigurationError,
				      "common_mounts must be an array"
			end

			begin
				@common_mounts.map! { |m| Mount.new(**symbolize_keys(m)) }
			rescue ArgumentError => ex
				case ex.message
				when /unknown keywords?: (.*)$/
					raise ConfigurationError,
						   "unknown mount option(s): #{$1}"
				when /missing keywords?: (.*)$/
					raise ConfigurationError,
					      "missing mount option(s): #{$1}"
				else
					#:nocov:
					raise
					#:nocov:
				end
			end
		end

		def validate_expose
			@logger.debug(logloc) { "@expose: #{@expose.inspect}" }
			unless @expose.is_a?(Array)
				raise ConfigurationError,
				      "expose must be an array"
			end

			@expose.map! do |e|
				e = e.to_s
				unless e.is_a?(String) && e =~ %r{\A\d+(/(tcp|udp))?\z}
					raise ConfigurationError,
					      "exposed ports must be integers, with an optional protocol specifier (got #{e.inspect})"
				end

				if $1.nil?
					e += "/tcp"
				end

				if e.to_i < 1 || e.to_i > 65535
					raise ConfigurationError,
					      "exposed port #{e} is out of range (expected 1-65535)"
				end

				e
			end
		end

		def validate_publish
			@logger.debug(logloc) { "@publish: #{@publish.inspect}" }
			unless @publish.is_a?(Array)
				raise ConfigurationError,
				      "publish must be an array"
			end

			unless @publish.all? { |p| String === p }
				raise ConfigurationError,
				      "publish elements must be strings"
			end

			@publish.each do |e|
				unless e =~ %r{\A(\d+(?:-\d+)?)?:(\d+)(?:-\d+)?(/(tcp|udp))?\z}
					raise ConfigurationError,
					      "invalid publish port spec #{e.inspect}"
				end

				if $2.to_i < 1 || $2.to_i > 65535
					raise ConfigurationError,
					      "publish port spec #{e} is out of range (expected 1-65535)"
				end

				if $1 && @system_config.port_whitelist[$1] != @name
					raise ConfigurationError,
					      "cannot bind to a non-whitelisted host port"
				end
			end
		end

		def validate_publish_all
			unless @publish_all == true || @publish_all == false
				raise ConfigurationError,
				      "publish_all must be either true or false"
			end
		end

		def symbolize_keys(h)
			{}.tap do |res|
				h.keys.each do |k|
					res[k.to_sym] = h[k]
				end
			end
		end
	end
end
