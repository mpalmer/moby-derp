require_relative "./config_file"

module MobyDerp
	class SystemConfig < ConfigFile
		attr_reader :mount_root, :port_whitelist, :network_name, :use_host_resolv_conf,
		            :cpu_count, :cpu_bits

		def initialize(config_data_or_filename, moby_info, logger)
			@logger = logger

			case config_data_or_filename
			when String
				super(config_data_or_filename)
			when Hash
				@config = stringify_keys(config_data_or_filename)
			else
				raise ArgumentError, "Unsupported type for config_data_or_filename parameter"
			end

			@mount_root           = @config["mount_root"]
			@port_whitelist       = stringify_keys(@config["port_whitelist"] || {})
			@network_name         = @config["network_name"] || "bridge"
			@use_host_resolv_conf = @config["use_host_resolv_conf"] || false

			@cpu_count = moby_info["NCPU"]
			# As far as I can tell, the only 32-bit platform Moby supports is
			# armhf; if that turns out to be incorrect, amend the list below.
			@cpu_bits  = %w{armhf}.include?(moby_info["Architecture"]) ? 32 : 64

			unless @mount_root.is_a?(String)
				raise ConfigurationError,
				      "mount_root must be a string"
			end

			unless @mount_root =~ /\A\//
				raise ConfigurationError,
				      "mount_root must be an absolute path"
			end

			unless @network_name.is_a?(String)
				raise ConfigurationError,
				      "network_name must be a string"
			end

			unless [true, false].include?(@use_host_resolv_conf)
				raise ConfigurationError,
				      "use_host_resolv_conf must be true or false"
			end
		end

		private

		def stringify_keys(h)
			{}.tap do |res|
				h.keys.each { |k| res[k.to_s] = h[k] }
			end
		end
	end
end
