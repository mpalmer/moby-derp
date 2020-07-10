require_relative "./freedom_patches/docker/image"
require_relative "./error"
require_relative "./mount"

require "docker-api"
require "shellwords"

module MobyDerp
	class ContainerConfig
		attr_reader :name, :image, :update_image, :command, :environment, :mounts,
		            :labels, :readonly, :stop_signal, :stop_timeout, :user, :restart, :limits,
		            :startup_health_check

		def initialize(system_config:,
		               pod_config:,
		               container_name:,
		               image:,
		               update_image: true,
		               command: [],
		               environment: {},
		               mounts: [],
		               labels: {},
		               readonly: false,
		               stop_signal: "SIGTERM",
		               stop_timeout: 10,
		               user: nil,
		               restart: "no",
		               limits: {},
		               startup_health_check: nil
		              )
			@system_config, @pod_config, @name, @image = system_config, pod_config, "#{pod_config.name}.#{container_name}", image

			@update_image, @command, @environment, @mounts, @labels = update_image, command, environment, mounts, labels
			@readonly, @stop_signal, @stop_timeout, @user, @restart = readonly, stop_signal, stop_timeout, user, restart
			@limits, @startup_health_check = limits, startup_health_check

			validate_image
			validate_update_image
			validate_command
			validate_environment
			validate_mounts
			validate_labels
			validate_readonly
			validate_stop_signal
			validate_stop_timeout
			validate_user
			validate_restart
			validate_limits
			validate_startup_health_check
		end

		private

		def validate_image
			unless @image.is_a?(String)
				raise ConfigurationError,
				      "image must be a string"
			end

			unless @image =~ Docker::Image::IMAGE_REFERENCE
				raise ConfigurationError,
				      "image is not a valid image reference"
			end

			if @image.match(Docker::Image::IMAGE_REFERENCE)[9].nil?
				@image += ":latest"
			end
		end

		def validate_update_image
			validate_boolean(:update_image)
		end

		def validate_command
			case @command
			when String
				# Despite the Docker Engine API spec saying you can pass a string,
				# if you do it doesn't get parsed into arguments... so that's pretty
				# fucking useless.
				@command = Shellwords.split(@command)
			when Array
				unless @command.all? { |c| String === c }
					raise ConfigurationError, "all elements of the command array must be strings"
				end
			else
				raise ConfigurationError,
				      "command must be string or array of strings"
			end
		end

		def validate_environment
			validate_hash(:environment)

			if (bad_vars = @environment.keys.select { |k| k =~ /=/ }) != []
				raise ConfigurationError,
				      "environment variable names cannot include equals signs: #{bad_vars.inspect}"
			end
		end

		def validate_mounts
			unless @mounts.is_a?(Array)
				raise ConfigurationError,
				      "mounts must be an array"
			end

			begin
				@mounts.map! { |m| Mount.new(**symbolize_keys(m)) }
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

		def validate_labels
			validate_hash(:labels)
		end

		def validate_readonly
			validate_boolean(:readonly)
		end

		def validate_stop_signal
			if @stop_signal.is_a?(String)
				signame = @stop_signal.sub(/\ASIG/, "")
				# This is not 100% accurate, because in theory moby-derp could
				# be running on a different platform to the Moby server it is
				# controlling, but we'll worry about that if we ever come to it.
				unless Signal.list.has_key?(signame)
					raise ConfigurationError,
					      "unknown signal name: #{@stop_signal.inspect}"
				end
			elsif @stop_signal.is_a?(Integer)
				unless Signal.list.values.include?(@stop_signal)
					raise ConfigurationError,
					      "unknown signal ID #{@stop_signal}"
				end
			else
				raise ConfigurationError,
				      "stop_signal must be a string or integer"
			end
		end

		def validate_stop_timeout
			unless @stop_timeout.is_a?(Integer)
				raise ConfigurationError,
				      "stop_timeout must be an integer"
			end

			if @stop_timeout < 0
				raise ConfigurationError,
				      "stop_timeout cannot be negative"
			end
		end

		def validate_user
			return if @user.nil?

			unless @user =~ /\A([a-zA-Z0-9_-]+)?(:[a-zA-Z0-9_-]+)?\z/
				raise ConfigurationError,
				      "invalid user specification"
			end
		end

		def validate_restart
			unless @restart.is_a?(String)
				raise ConfigurationError,
				      "restart must be a string"
			end

			unless @restart =~ /\Ano|on-failure(:\d+)?|always|unless-stopped\z/
				raise ConfigurationError,
				      "invalid value for restart parameter"
			end
		end

		KNOWN_LIMITS = %w{
			cpus cpu-shares memory memory-swap memory-reservation oom-score-adj
			pids shm-size ulimit-core ulimit-cpu ulimit-data ulimit-fsize
			ulimit-memlock ulimit-msgqueue ulimit-nofile ulimit-rttime ulimit-stack
		}

		def validate_limits
			unless @limits.is_a?(Hash)
				raise ConfigurationError,
				      "limits must be a map"
			end

			if (bad_keys = @limits.keys - KNOWN_LIMITS) != []
				raise ConfigurationError,
				      "unknown limit(s): #{bad_keys.inspect}"
			end

			validate_cpus_limit
			validate_cpushares_limit
			validate_memory_limit
			validate_memoryswap_limit
			validate_memoryreservation_limit
			validate_oomscoreadj_limit
			validate_pids_limit
			validate_shmsize_limit
			validate_ulimits
		end

		def validate_cpus_limit
			return unless @limits.has_key?("cpus")

			unless @limits["cpus"].is_a?(Numeric)
				raise ConfigurationError,
				      "cpus limit must be a number"
			end

			if @limits["cpus"] <= 0
				raise ConfigurationError,
				      "cpus limit must be a positive number"
			end

			if @limits["cpus"] > @system_config.cpu_count
				raise ConfigurationError,
					"cannot use #{@limits["cpus"]}, as the system only has #{@system_config.cpu_count} CPUs"
			end
		end

		def validate_cpushares_limit
			return unless @limits.has_key?("cpu-shares")

			unless @limits["cpu-shares"].is_a?(Integer)
				raise ConfigurationError,
				      "cpu-shares limit must be an integer"
			end

			unless (2..1024).include?(@limits["cpu-shares"])
				raise ConfigurationError,
				      "cpu-shares limit must be an integer between 2 and 1024 inclusive"
			end
		end

		def validate_memory_limit
			validate_memory_type_limit("memory")
		end

		def validate_memoryswap_limit
			validate_memory_type_limit("memory-swap")
		end

		def validate_memoryreservation_limit
			validate_memory_type_limit("memory-reservation")
		end

		def validate_oomscoreadj_limit
			return unless @limits.has_key?("oom-score-adj")

			unless @limits["oom-score-adj"].is_a?(Integer)
				raise ConfigurationError,
				      "oom-score-adj limit must be an integer"
			end

			unless (0..1000).include?(@limits["oom-score-adj"])
				raise ConfigurationError,
				      "oom-score-adj limit must be an integer between 0 and 1000 inclusive"
			end
		end

		def validate_pids_limit
			return unless @limits.has_key?("pids")

			unless @limits["pids"].is_a?(Integer)
				raise ConfigurationError,
				      "pids limit must be an integer"
			end

			# As far as I can see, the only 32-bit platform that Moby supports is
			# armhf.  Extend the list if required.
			max_pids = @system_config.cpu_bits == 32 ? 2**15 : 2**22

			unless (-1..max_pids).include?(@limits["pids"])
				raise ConfigurationError,
				      "pids limit must be an integer between -1 and #{max_pids} inclusive"
			end
		end

		def validate_shmsize_limit
			validate_memory_type_limit("shm-size")
		end

		def validate_ulimits
			@limits.keys.grep(/\Aulimit-.*\z/).each do |ulimit|
				unless @limits[ulimit] =~ /\A(unlimited|\d+)(:(unlimited|\d+))?\z/
					raise ConfigurationError,
					      "invalid limit syntax for #{ulimit}: must be <softlimit>[:<hardlimit>]"
				end

				@limits[ulimit] = [ulimit_value($1)]

				if $2.nil?
					@limits[ulimit][1] = @limits[ulimit][0]
				else
					@limits[ulimit][1] = ulimit_value($3)
				end
			end
		end

		def ulimit_value(s)
			if s == "unlimited"
				-1
			else
				s.to_i
			end
		end

		def validate_memory_type_limit(name)
			return unless @limits.has_key?(name)

			case @limits[name]
			when Integer
				if @limits[name] < 0
					raise ConfigurationError,
					      "#{name} limit must not be a negative number"
				end
			when String
				unless @limits[name] =~ /\A(\d+(\.\d+)?)([kKmMgGtTpP]?)[bB]?\z/
					raise ConfigurationError,
					      "invalid value for #{name} limit: #{@limits[name]}"
				end
				@limits[name] = ($1.to_f * multiplier($3)).to_i
			else
				raise ConfigurationError,
				      "#{name} limit must be a string or an integer"
			end
		end

		def validate_startup_health_check
			if @startup_health_check.nil?
				# This is fine
				return
			end

			unless @startup_health_check.is_a?(Hash)
				raise ConfigurationError,
				      "startup_health_check must be a hash"
			end

			case @startup_health_check[:command]
			when String
				@startup_health_check[:command] = Shellwords.split(@startup_health_check[:command])
			when Array
				unless @startup_health_check[:command].all? { |c| String === c }
					raise ConfigurationError, "all elements of the health check command array must be strings"
				end
			when NilClass
				raise ConfigurationError, "health check command must be specified"
			else
				raise ConfigurationError,
				      "health check command must be string or array of strings"
			end

			@startup_health_check[:interval] ||= 3
			@startup_health_check[:attempts] ||= 10

			unless Numeric === @startup_health_check[:interval]
				raise ConfigurationError, "startup health check interval must be a number"
			end

			if @startup_health_check[:interval] < 0
				raise ConfigurationError, "startup health check interval cannot be negative"
			end

			unless Integer === @startup_health_check[:attempts]
				raise ConfigurationError, "startup health check attempt count must be an integer"
			end

			if @startup_health_check[:attempts] < 1
				raise ConfigurationError, "startup health check attempt count must be a positive integer"
			end
		end

		def validate_boolean(name)
			v = instance_variable_get(:"@#{name}")
			unless v == true || v == false
				raise ConfigurationError,
				      "#{name} setting must be a boolean"
			end
		end

		def validate_hash(name)
			h = instance_variable_get(:"@#{name}")

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

		def symbolize_keys(h)
			{}.tap do |res|
				h.keys.each do |k|
					res[k.to_sym] = h[k]
				end
			end
		end

		def multiplier(s)
			case s.upcase
			when ''
				1
			when 'K'
				1024
			when 'M'
				1024 * 1024
			when 'G'
				1024 * 1024 * 1024
			when 'T'
				1024 * 1024 * 1024 * 1024
			when 'P'
				1024 * 1024 * 1024 * 1024 * 1024
			else
				#:nocov:
				raise ConfigurationError,
				      "Unknown suffix #{s.inspect}"
				#:nocov:
			end
		end

	end
end
