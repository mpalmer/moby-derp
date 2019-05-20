require_relative "./container"
require_relative "./logging_helpers"

module MobyDerp
	class Pod
		include LoggingHelpers

		attr_reader :logger

		def initialize(pod_config)
			@config = pod_config
			@logger = pod_config.logger
		end

		def run
			@logger.info(logloc) { "Checking root container" }
			@root_container_id = root_container.run

			@logger.debug(logloc) { "Root container ID is #{@root_container_id}" }

			@config.containers.each do |cfg|
				@logger.info(logloc) { "Checking container #{cfg.name}" }

				begin
					MobyDerp::Container.new(pod: self, container_config: cfg).run
				rescue MobyDerp::ContainerError => ex
					raise MobyDerp::ContainerError,
					      "error while running container #{cfg.name}: #{ex.message}",
							ex.backtrace
				end
			end
		end

		def name
			@config.name
		end

		def root_container_id
			if @root_container_id.nil?
				raise MobyDerp::BugError,
				      "root_container_id requested before root container was spawned"
			else
				@root_container_id
			end
		end

		def common_labels
			@config.common_labels
		end

		def root_labels
			@config.root_labels
		end

		def common_environment
			@config.common_environment
		end

		def common_mounts
			@config.common_mounts
		end

		def mount_root
			@config.mount_root
		end

		def network_name
			@config.network_name
		end

		def hostname
			@config.hostname
		end

		def expose
			@config.expose
		end

		private

		def root_container
			MobyDerp::Container.new(pod: self, container_config: root_container_config, root_container: true)
		end

		def root_container_config
			MobyDerp::ContainerConfig.new(
				system_config:  @config.system_config,
				pod_config:     @config,
				container_name: "root",
				image:          "gcr.io/google_containers/pause-amd64:3.0",
				labels:         @config.root_labels,
				readonly:       true,
				restart:        "always",
			)
		end
	end
end
