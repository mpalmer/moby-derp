require_relative "./logging_helpers"

require "digest/sha2"
require "docker-api"
require "ipaddr"
require "json/canonicalization"

require_relative "./freedom_patches/docker/credential"

module MobyDerp
	class Container
		include LoggingHelpers

		def initialize(pod:, container_config:, root_container: false)
			@logger = pod.logger

			@pod, @config, @root_container = pod, container_config, root_container
		end

		def run
			container_name = @root_container ? @pod.name : @config.name
			@logger.debug(logloc) { "Calculated container name is #{container_name} (@root_container: #{@root_container.inspect}, @config.name: #{@config.name}, @pod.name: #{@pod.name}" }

			begin
				existing_container = Docker::Container.get(container_name)
				@logger.debug(logloc) { "Config hash for existing container #{container_name} is #{existing_container.info["Config"]["Labels"]["org.hezmatt.moby-derp.config-hash"].inspect}" }
				@logger.debug(logloc) { "New config hash is #{params_hash(container_creation_parameters).inspect}" }

				if existing_container.info["Config"]["Labels"]["org.hezmatt.moby-derp.config-hash"] == params_hash(container_creation_parameters)
					# Container is up-to-date
					@logger.info(logloc) { "Container #{container_name} is up-to-date" }

					if @config.restart == "always" && existing_container.info.dig("State", "Status") != "running"
						existing_container.start
					end

					return existing_container.id
				end

				if existing_container.info["Config"]["Labels"]["org.hezmatt.moby-derp.pod-name"] != @pod.name
					raise ContainerError,
					      "container #{container_name} is not tagged as being part of this pod"
				end
				@logger.info(logloc) { "Deleting container #{container_name} (#{existing_container.id[0..11]}) because it is out-of-date" }
				existing_container.delete(force: true)
				@logger.info(logloc) { "Creating new container #{container_name}" }
			rescue Docker::Error::NotFoundError
				@logger.info(logloc) { "Container #{container_name} does not exist; creating it" }
				# Container doesn't exist, need to create it
			end

			begin
				c = Docker::Container.create(hash_labelled(container_creation_parameters))
				c.start!.object_id

				if @config.startup_health_check
					attempts = @config.startup_health_check[:attempts]

					while attempts > 0
						stdout, stderr, exitstatus = c.exec(@config.startup_health_check[:command])
						if exitstatus > 0
							stdout_lines = stdout.empty? ? [] : ["stdout:"] + stdout.join("\n").split("\n").map { |l| "  #{l}" }
							stderr_lines = stderr.empty? ? [] : ["stderr:"] + stderr.join("\n").split("\n").map { |l| "  #{l}" }
							output_lines = stdout_lines + stderr_lines
							@logger.warn(logloc) { "Startup health check failed on #{container_name} with status #{exitstatus}." + (output_lines.empty? ? "" : (["  Output:"] + output_lines.join("\n  "))) }

							attempts -= 1
							sleep @config.startup_health_check[:interval]
						else
							@logger.info(logloc) { "Startup health check passed." }
							break
						end
					end

					if attempts == 0
						raise MobyDerp::StartupHealthCheckError,
							"Container #{container_name} has failed the startup health check command #{@config.startup_health_check[:attempts]} times.  Aborting."
					end
				end

				c.id
			rescue Docker::Error::ClientError => ex
				raise MobyDerp::ContainerError,
				      "moby daemon returned error: #{ex.message}"
			end
		end

		private

		def container_creation_parameters
			{}.tap do |params|
				if @root_container
					params["Hostname"] = @pod.hostname
					params["HostConfig"] = {
						"NetworkMode" => @pod.network_name,
						"Init"        => true,
						"IpcMode"     => "shareable"
					}
					params["MacAddress"] = container_mac_address
					if network_uses_ipv6? && user_defined_network?
						params["NetworkingConfig"] = {
							"EndpointsConfig" => {
								@pod.network_name => {
									"IPAMConfig" => {
										"IPv6Address" => container_ipv6_address,
									}
								}
							}
						}
					end
					params["ExposedPorts"] = Hash[@pod.expose.map { |ex| [ex, {}] }]
				else
					params["HostConfig"] = {
						"NetworkMode"   => "container:#{@pod.root_container_id}",
						"PidMode"       => "container:#{@pod.root_container_id}",
						"IpcMode"       => "container:#{@pod.root_container_id}",
					}
				end

				params["HostConfig"]["RestartPolicy"] = parsed_restart_policy
				params["HostConfig"]["Mounts"]        = merged_mounts.map { |mount| mount_structure(mount) }

				params["Env"]        = @pod.common_environment.merge(@config.environment).map { |k, v| "#{k}=#{v}" }
				params["Volumes"]    = {}

				params["name"]  = @root_container ? @pod.name : @config.name
				params["Image"] = image_id

				params["Cmd"]         = @config.command
				params["StopSignal"]  = @config.stop_signal
				params["StopTimeout"] = @config.stop_timeout

				if @config.user
					params["User"] = @config.user
				end

				if @config.readonly
					params["HostConfig"]["ReadonlyRootfs"] = true
				end

				if @config.limits["cpus"]
					params["HostConfig"]["NanoCPUs"] = @config.limits["cpus"] * 10 ** 9
				end

				{
					"cpu-shares"         => "CpuShares",
					"oom-score-adj"      => "OomScoreAdj",
					"pids"               => "PidsLimit",
					"memory"             => "Memory",
					"memory-swap"        => "MemorySwap",
					"memory-reservation" => "MemoryReservation",
					"shm-size"           => "ShmSize",
				}.each do |limit_name, moby_limit_name|
					if @config.limits[limit_name]
						params["HostConfig"][moby_limit_name] = @config.limits[limit_name]
					end
				end

				@config.limits.keys.grep(/^ulimit-/).each do |ulimit|
					params["HostConfig"]["Ulimits"] ||= []
					params["HostConfig"]["Ulimits"] << ulimit_structure(ulimit)
				end

				params["Labels"] = @pod.common_labels.merge(@config.labels)
				params["Labels"]["org.hezmatt.moby-derp.pod-name"] = @pod.name

				if @root_container
					params["Labels"] = @pod.root_labels.merge(params["Labels"])
				else
					params["Labels"]["org.hezmatt.moby-derp.root-container-id"] = @pod.root_container_id
				end
			end
		end

		def hash_labelled(params)
			params.tap do |params|
				config_hash = params_hash(params)

				params["Labels"] ||= {}
				params["Labels"]["org.hezmatt.moby-derp.config-hash"] = config_hash
			end
		end

		def params_hash(params)
			"sha256:#{Digest::SHA256.hexdigest(params.to_json_c14n)}"
		end

		def image_id
			if @config.image =~ /\A#{Docker::Image::DIGEST}\z/
				@config.image
			else
				if @config.update_image
					begin
						Docker::Image.create(fromImage: @config.image).id
					rescue Docker::Error::NotFoundError
						raise ContainerError,
								"image #{@config.image} for container #{@config.name} cannot be downloaded"
					end
				else
					begin
						Docker::Image.get(@config.image).id
					rescue Docker::Error::NotFoundError
						# Image doesn't exist locally, so we'll have to pull it after all
						begin
							Docker::Image.create(fromImage: @config.image).id
						rescue Docker::Error::NotFoundError
							raise ContainerError,
							      "image #{@config.image} for container #{@config.name} cannot be downloaded"
						end
					end
				end
			end
		end

		def parsed_restart_policy
			@config.restart =~ /\A([a-z-]+)(:(\d+))?\z/
			{ "Name" => $1 }.tap do |policy|
				if $3
					policy["MaximumRetryCount"] = $3.to_i
				end
			end
		end

		def merged_mounts
			container_mount_targets = @config.mounts.map { |m| m.target }

			@config.mounts + @pod.common_mounts.select { |m| !container_mount_targets.include?(m.target) }
		end

		def mount_structure(mount)
			{
				"Type"     => "bind",
				"Source"   => mount.source[0] == "/" ? mount.source : "#{@pod.mount_root}/#{mount.source}",
				"Target"   => mount.target,
				"ReadOnly" => mount.readonly,
			}
		end

		def ulimit_structure(limit_key)
			{
				"Name" => limit_key.sub(/^ulimit-/, ''),
				"Soft" => @config.limits[limit_key].first,
				"Hard" => @config.limits[limit_key].last,
			}
		end

		def container_mac_address
			"02:" + Digest::SHA256.hexdigest(@pod.name + Socket.gethostname)[0..9].scan(/../).join(":")
		end

		def docker_network
			begin
				network = Docker::Network.get(@pod.network_name)
			rescue Docker::Error::NotFoundError
				raise ContainerError,
				      "network #{@pod.network_name} does not exist"
			end
		end

		def network_uses_ipv6?
			docker_network.info["EnableIPv6"]
		end

		def user_defined_network?
			!%w{bridge host none}.include?(@pod.network_name)
		end

		def container_ipv6_address
			network, masklen = ipv6_network.split("/", 2)
			network = IPAddr.new(network)
			masklen = masklen.to_i

			(network | Digest::SHA256.hexdigest(container_mac_address).to_i(16) % 2**masklen).to_s
		end

		def ipv6_network
			ipam = docker_network.info["IPAM"]
			unless ipam["Driver"] == "default"
				raise ContainerError,
				      "Unsupported IPAM driver #{ipam["Driver"]} on network #{@pod.network_name}"
			end

			begin
				ipam["Config"].find do |cfg|
					IPAddr.new(cfg["Subnet"]).ipv6?
				end["Subnet"]
			rescue NoMethodError
				raise ContainerError,
				      "No IPv6 subnet found on network #{@pod.network_name}"
			end
		end
	end
end
