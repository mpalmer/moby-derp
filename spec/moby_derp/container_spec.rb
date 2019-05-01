require_relative "../spec_helper"

require "moby_derp/container"
require "moby_derp/container_config"
require "moby_derp/pod"
require "moby_derp/pod_config"
require "moby_derp/system_config"

require "deep_merge"

describe MobyDerp::Container do
	uses_logger

	let(:system_config)         { instance_double(MobyDerp::SystemConfig) }
	let(:pod_config)            { instance_double(MobyDerp::PodConfig) }
	let(:pod)                   { instance_double(MobyDerp::Pod) }
	let(:container_name)        { "bob" }
	let(:base_options)          { { image: "bob:latest" } }
	let(:container_options)     { base_options }
	let(:container_config)      { MobyDerp::ContainerConfig.new(system_config: system_config, pod_config: pod_config, container_name: container_name, **container_options) }
	let(:container)             { MobyDerp::Container.new(pod: pod, container_config: container_config) }
	let(:mock_docker_container) { instance_double(Docker::Container) }

	before(:each) do
		allow(system_config).to receive(:cpu_count).and_return(4)
		allow(system_config).to receive(:cpu_bits).and_return(64)
		allow(pod_config).to receive(:name).and_return("spec-pod")
		allow(pod).to receive(:name).and_return("spec-pod")
		allow(pod).to receive(:root_container_id).and_return("xyz987")
		allow(pod).to receive(:common_labels).and_return({})
		allow(pod).to receive(:common_environment).and_return({})
		allow(pod).to receive(:common_mounts).and_return([])
		allow(pod).to receive(:mount_root).and_return("/srv/docker/my-pod")
		allow(pod).to receive(:logger).and_return(logger)
		allow(Docker::Image)
			.to receive(:create)
			.with(fromImage: "bob:latest")
			.and_return(mock_image = instance_double(Docker::Image))
		allow(mock_image).to receive(:id).and_return("sha256:imgimgimgimg")
		allow(Docker::Container).to receive(:get).and_raise(Docker::Error::NotFoundError)
		allow(Docker::Container).to receive(:create).and_return(mock_docker_container)
		allow(mock_docker_container).to receive(:start!).and_return(mock_docker_container)
		allow(mock_docker_container).to receive(:id).and_return("mockmockmockid")
	end

	describe "#run" do
		context "with no existing container" do
			before(:each) do
				allow(Docker::Container).to receive(:get).with("spec-pod.bob").and_raise(Docker::Error::NotFoundError)

			end

			it "tells Docker to start a new container" do
				expect(Docker::Container)
					.to receive(:create)
					.with(any_args)
				expect(mock_docker_container).to receive(:start!)

				container.run
			end
		end

		context "with an existing container with the same config hash" do
			let(:mock_docker_container) { instance_double(Docker::Container) }
			before(:each) do
				allow(Docker::Container).to receive(:get).with("spec-pod.bob").and_return(mock_docker_container)
				allow(mock_docker_container)
					.to receive(:info)
					.and_return(
						"Config" => {
							"Labels" => {
								"org.hezmatt.moby-derp.config-hash"       => "sha256:495184c751c8e6962ddf4fbaca5a2a5fae07bf7b17724f189b76e4b73cef8215",
								"org.hezmatt.moby-derp.pod-name"          => "spec-pod",
								"org.hezmatt.moby-derp.root-container-id" => "xyz987",
							}
						}
					)
			end

			it "does not touch Docker" do
				expect(Docker::Container).to receive(:get)
				expect(Docker::Container).to_not receive(:create)
				expect(mock_docker_container).to_not receive(:delete)

				container.run
			end
		end

		context "with an existing container with a different config hash" do
			before(:each) do
				allow(Docker::Container).to receive(:get).with("spec-pod.bob").and_return(mock_docker_container)
				allow(mock_docker_container)
					.to receive(:info)
					.and_return(
						"Config" => {
							"Labels" => {
								"org.hezmatt.moby-derp.config-hash" => "sha256:nottherighthash",
								"org.hezmatt.moby-derp.pod-name"    => "spec-pod",
							}
						}
					)
			end

			it "nukes the existing container and creates a new one" do
				expect(mock_docker_container).to receive(:delete).with(force: true)
				expect(Docker::Container)
					.to receive(:create)
					.with(any_args)
					.and_return(new_mock_docker_container = instance_double(Docker::Container))
				expect(new_mock_docker_container).to receive(:start!).with(no_args).and_return(mock_docker_container)

				container.run
			end
		end

		context "with an existing container that isn't moby-derp-tagged" do
			before(:each) do
				allow(Docker::Container).to receive(:get).and_return(mock_docker_container)
				allow(mock_docker_container)
					.to receive(:info)
					.and_return("Config" => { "Labels" => {} })
			end

			it "doesn't touch docker and raises an exception" do
				expect(Docker::Container).to receive(:get)
				expect(Docker::Container).to_not receive(:create)
				expect(mock_docker_container).to_not receive(:delete)

				expect { container.run }.to raise_error(MobyDerp::ContainerError)
			end
		end

		context "when the specified image can't be found" do
			before(:each) do
				allow(Docker::Image)
					.to receive(:create)
					.with(fromImage: "bob:latest")
					.and_raise(Docker::Error::NotFoundError)
			end

			it "raises a relevant exception" do
				expect(Docker::Container).to_not receive(:create)

				expect { container.run }.to raise_error(MobyDerp::ContainerError)
			end
		end

		context "when the image is a digest" do
			let(:container_options) { base_options.merge(image: "sha256:" + "01234567" * 8) }

			it "doesn't try to pull the image" do
				expect(Docker::Image).to_not receive(:create)

				container.run
			end

			it "does create the container" do
				expect(Docker::Container)
					.to receive(:create)
					.with(any_args)
				expect(mock_docker_container).to receive(:start!).with(no_args)

				container.run
			end
		end

		context "with update_image: false" do
			let(:container_options) { base_options.merge(update_image: false) }

			context "when the image exists locally" do
				before(:each) do
					allow(Docker::Image).to receive(:get).with("bob:latest").and_return(mock_image = instance_double(Docker::Image))
					allow(mock_image).to receive(:id).and_return("sha256:abc1234xyz")
				end

				it "doesn't try to pull the image" do
					expect(Docker::Image).to_not receive(:create)

					container.run
				end

				it "does create the container" do
					expect(Docker::Container)
						.to receive(:create)
						.with(any_args)
					expect(mock_docker_container).to receive(:start!).with(no_args)

					container.run
				end
			end

			context "when the image doesn't exist locally" do
				before(:each) do
					allow(Docker::Image).to receive(:get).with("bob:latest").and_raise(Docker::Error::NotFoundError)
				end

				it "pulls the image" do
					expect(Docker::Image).to receive(:create).with(fromImage: "bob:latest")

					expect(Docker::Container)
						.to receive(:create)
						.with(any_args)
						.and_return(new_mock_docker_container = instance_double(Docker::Container))
					expect(new_mock_docker_container).to receive(:start!).with(no_args).and_return(mock_docker_container)

					container.run
				end

				context "and the pull fails" do
					before(:each) do
						allow(Docker::Image).to receive(:create).with(fromImage: "bob:latest").and_raise(Docker::Error::NotFoundError)
					end

					it "raises a relevant exception" do
						expect { container.run }.to raise_error(MobyDerp::ContainerError)
					end
				end
			end
		end

		context "with labels set in the container config" do
			let(:container_options) { base_options.merge(labels: { "foo" => "bar", "baz" => "wombat" }) }

			it "sets the labels in the created container" do
				expect(Docker::Container).to receive(:create) do |create_config|
					expect(create_config["Labels"]["foo"]).to eq("bar")
					expect(create_config["Labels"]["baz"]).to eq("wombat")
					mock_docker_container
				end

				container.run
			end

			context "that override internal labels" do
				let(:container_options) { base_options.merge(labels: { "org.hezmatt.moby-derp.config-hash" => "ohai!" }) }

				it "overrides them with the moby-derp value" do
					expect(Docker::Container).to receive(:create) do |create_config|
						expect(create_config["Labels"]["org.hezmatt.moby-derp.config-hash"]).to_not eq("ohai!")
						mock_docker_container
					end

					container.run
				end
			end

			context "and the same labels on the pod" do
				before(:each) do
					allow(pod).to receive(:common_labels).and_return("foo" => "flibbetygibbets")
				end

				it "prefers the container's label" do
					expect(Docker::Container).to receive(:create) do |create_config|
						expect(create_config["Labels"]["foo"]).to eq("bar")
						mock_docker_container
					end

					container.run
				end
			end
		end

		context "with environment set in the container config" do
			let(:container_options) { base_options.merge(environment: { "FOO" => "bar", "BAZ" => "wombat" }) }

			it "sets the environment in the created container" do
				expect(Docker::Container).to receive(:create) do |create_config|
					expect(create_config["Env"]).to include("FOO=bar")
					expect(create_config["Env"]).to include("BAZ=wombat")
					mock_docker_container
				end

				container.run
			end

			context "and the same environment variable on the pod" do
				before(:each) do
					allow(pod).to receive(:common_environment).and_return("FOO" => "flibbetygibbets")
				end

				it "prefers the container's value" do
					expect(Docker::Container).to receive(:create) do |create_config|
						expect(create_config["Env"]).to include("FOO=bar")
						expect(create_config["Env"]).to_not include("FOO=flibbetygibbets")
						mock_docker_container
					end

					container.run
				end
			end
		end

		context "with mounts set in the container config" do
			let(:container_options) do
				base_options.merge(mounts: [{ "source" => "babble", "target" => "/app", readonly: true }])
			end

			it "sets the mount config in the created container" do
				expect(Docker::Container).to receive(:create) do |create_config|
					expect(create_config["HostConfig"]["Mounts"])
						.to eq(
							[
								{
									"Type"     => "bind",
									"Source"   => "/srv/docker/my-pod/babble",
									"Target"   => "/app",
									"ReadOnly" => true,
								}
							]
						)
					mock_docker_container
				end

				container.run
			end

			context "and the same mount target on the pod" do
				before(:each) do
					allow(pod).to receive(:common_mounts).and_return([MobyDerp::Mount.new(source: "waffles", target: "/app")])
				end

				it "prefers the container's value" do
					expect(Docker::Container).to receive(:create) do |create_config|
						expect(create_config["HostConfig"]["Mounts"])
							.to eq(
								[
									{
										"Type"     => "bind",
										"Source"   => "/srv/docker/my-pod/babble",
										"Target"   => "/app",
										"ReadOnly" => true,
									}
								]
							)
						mock_docker_container
					end

					container.run
				end
			end
		end

		context "when the create assplodes" do
			before(:each) do
				allow(Docker::Container).to receive(:create).and_raise(Docker::Error::ClientError)
			end

			it "raises an appropriate exception" do
				expect { container.run }.to raise_error(MobyDerp::ContainerError)
			end
		end

		{
			"no options" => [
				{},
				{},
			],
			"a command string" => [
				{ command: "--foo --bar" },
				{ "Cmd" => "--foo --bar" },
			],
			"a command array" => [
				{ command: ["--foo", "--bar"] },
				{ "Cmd" => ["--foo", "--bar"] },
			],
			"readonly: true" => [
				{ readonly: true },
				{
					"HostConfig" => {
						"ReadonlyRootfs" => true,
					},
				},
			],
			"a custom stop_signal" => [
				{ stop_signal: "SIGABRT" },
				{ "StopSignal" => "SIGABRT" },
			],
			"a custom stop_timeout" => [
				{ stop_timeout: 42 },
				{ "StopTimeout" => 42 },
			],
			"restart: always" => [
				{ restart: "always" },
				{
					"HostConfig" => {
						"RestartPolicy" => {
							"Name" => "always",
						},
					},
				},
			],
			"restart: on-failure" => [
				{ restart: "on-failure:42" },
				{
					"HostConfig" => {
						"RestartPolicy" => {
							"Name"              => "on-failure",
							"MaximumRetryCount" => 42,
						},
					},
				},
			],
			"user set" => [
				{ user: "bob:12345" },
				{ "User" => "bob:12345" },
			],
			"limited CPU" => [
				{ limits: { "cpus" => 1.9 } },
				{
					"HostConfig" => {
						"NanoCPUs" => 1900000000,
					},
				},
			],
			"limited CPU shares" => [
				{ limits: { "cpu-shares" => 420 } },
				{
					"HostConfig" => {
						"CpuShares" => 420,
					},
				},
			],
			"limited memory" => [
				{ limits: { "memory" => "2G" } },
				{
					"HostConfig" => {
						"Memory" => 2 * 1024 * 1024 * 1024,
					},
				},
			],
			"memory in bytes" => [
				{ limits: { "memory" => "1048576" } },
				{
					"HostConfig" => {
						"Memory" => 1048576,
					},
				},
			],
			"memory in kB" => [
				{ limits: { "memory" => "2kB" } },
				{
					"HostConfig" => {
						"Memory" => 2 * 1024,
					},
				},
			],
			"memory in TB" => [
				{ limits: { "memory" => "2TB" } },
				{
					"HostConfig" => {
						"Memory" => 2 * 1024 * 1024 * 1024 * 1024,
					},
				},
			],
			"memory in PB" => [
				{ limits: { "memory" => "2PB" } },
				{
					"HostConfig" => {
						"Memory" => 2 * 1024 * 1024 * 1024 * 1024 * 1024,
					},
				},
			],
			"limited swap+memory" => [
				{ limits: { "memory-swap" => 3_123_456_789 } },
				{
					"HostConfig" => {
						"MemorySwap" => 3_123_456_789,
					},
				},
			],
			"limited memory reservation" => [
				{ limits: { "memory-reservation" => "1.2G" } },
				{
					"HostConfig" => {
						"MemoryReservation" => (1.2 * 1024 * 1024 * 1024).to_i,
					},
				},
			],
			"custom SHM size limit" => [
				{ limits: { "shm-size" => "200M" } },
				{
					"HostConfig" => {
						"ShmSize" => 200 * 1024 * 1024,
					},
				},
			],
			"non-standard OOM score adjustment" => [
				{ limits: { "oom-score-adj" => 42 } },
				{
					"HostConfig" => {
						"OomScoreAdj" => 42,
					},
				},
			],
			"lower PID limit" => [
				{ limits: { "pids" => 42 } },
				{
					"HostConfig" => {
						"PidsLimit" => 42,
					},
				},
			],
			"custom ulimits" => [
				{
					limits: {
						"ulimit-core"   => "unlimited",
						"ulimit-cpu"    => "42",
						"ulimit-fsize"  => "10000:20000",
						"ulimit-nofile" => "1000:unlimited",
					}
				},
				{
					"HostConfig" => {
						"Ulimits" => [
							{
								"Name" => "core",
								"Soft" => -1,
								"Hard" => -1,
							},
							{
								"Name" => "cpu",
								"Soft" => 42,
								"Hard" => 42,
							},
							{
								"Name" => "fsize",
								"Soft" => 10000,
								"Hard" => 20000,
							},
							{
								"Name" => "nofile",
								"Soft" => 1000,
								"Hard" => -1,
							},
						],
					},
				},
			],
		}.each do |desc, opts|
			context "with #{desc}" do
				let(:container_options) { base_options.merge(opts.first) }

				it "includes the appropriate options in the container" do
					expect(Docker::Container)
						.to receive(:create)
						.with(
							{
								"name"        => "spec-pod.bob",
								"Image"       => "sha256:imgimgimgimg",
								"Cmd"         => [],
								"HostConfig"  => {
									"NetworkMode"   => "container:xyz987",
									"IpcMode"       => "container:xyz987",
									"PidMode"       => "container:xyz987",
									"RestartPolicy" => {
										"Name" => "no",
									},
									"Mounts"        => [],
								},
								"StopSignal"  => "SIGTERM",
								"StopTimeout" => 10,
								"Volumes"     => {},
								"Env"         => [],
								"Labels"      => {
									"org.hezmatt.moby-derp.config-hash"       => match(/\Asha256:[0-9a-f]{64}\z/),
									"org.hezmatt.moby-derp.pod-name"          => "spec-pod",
									"org.hezmatt.moby-derp.root-container-id" => "xyz987",
								},
							}.deep_merge!(opts.last),
						)
						.and_return(mock_docker_container)
					expect(mock_docker_container).to receive(:start!).with(no_args)

					container.run
				end
			end
		end

		context "on a root container" do
			let(:container_options) { base_options }
			let(:container)         { MobyDerp::Container.new(pod: pod, container_config: container_config, root_container: true) }
			let(:mock_docker_network) { instance_double(Docker::Network) }

			before(:each) do
				allow(pod).to receive(:network_name).and_return("bridge")
				allow(pod).to receive(:hostname).and_return("bob-spec")
				allow(Docker::Network).to receive(:get).with("bridge").and_return(mock_docker_network)
				allow(mock_docker_network)
					.to receive(:info)
					.and_return("EnableIPv6" => false)
			end

			it "spawns a whole different sort of container" do
				expect(Docker::Container)
					.to receive(:create) do |create_options|
						# These are just the things that setting root_container: true
						# directly changes.  Lots of other things, configured by regular
						# config parameters, also need to be adjusted to make a "proper"
						# root container.
						expect(create_options["name"]).to eq("spec-pod")
						expect(create_options["HostConfig"]["Init"]).to eq(true)
						expect(create_options["HostConfig"]["NetworkMode"]).to eq("bridge")
						expect(create_options["HostConfig"]).to_not have_key("IpcMode")
						expect(create_options["HostConfig"]).to_not have_key("PidMode")
						expect(create_options["Labels"]).to_not have_key("org.hezmatt.moby-derp.root-container-id")
						expect(create_options["MacAddress"]).to match(/\A02(:[0-9a-f]{2}){5}\z/)
						mock_docker_container
					end
				expect(mock_docker_container).to receive(:start!).with(no_args)

				container.run
			end

			context "with an invalid network name" do
				before(:each) do
					allow(Docker::Network).to receive(:get).with("bridge").and_raise(Docker::Error::NotFoundError)
				end

				it "raises an appropriate exception" do
					expect { container.run }.to raise_error(MobyDerp::ContainerError)
				end
			end

			context "with an IPv6 network" do
				before(:each) do
					allow(Docker::Network).to receive(:get).with("bridge").and_return(mock_docker_network)
					allow(mock_docker_network)
						.to receive(:info)
						.and_return(
							"EnableIPv6" => true,
							"IPAM"       => {
								"Driver" => "default",
								"Config" => [
									{
										"Subnet" => "192.0.2.0/24",
										"Gateway" => "192.0.2.1",
									},
									{
										"Subnet"  => "2001:db8::/64",
										"Gateway" => "2001:db8::1",
									},
								],
							},
						)
				end

				it "allocates an IPv6 address from the appropriate pool" do
					expect(Docker::Container)
						.to receive(:create) do |create_options|
							expect(create_options["NetworkingConfig"])
								.to match(
									"EndpointsConfig" => {
										"bridge" => {
											"IPAMConfig" => {
												"IPv6Address" => match(/\A2001:db8::[0-9a-f:]+\z/)
											}
										}
									}
								)
							mock_docker_container
						end
					expect(mock_docker_container).to receive(:start!).with(no_args)

					container.run
				end

				context "with a custom IPAM driver" do
					before(:each) do
						allow(Docker::Network).to receive(:get).with("bridge").and_return(mock_docker_network)
						allow(mock_docker_network)
							.to receive(:info)
							.and_return(
								"EnableIPv6" => true,
								"IPAM"       => {
									"Driver" => "waluigi",
								},
							)
					end

					it "raises an appropriate exception" do
						expect { container.run }.to raise_error(MobyDerp::ContainerError)
					end
				end

				context "with no IPv6 subnets" do
					before(:each) do
						allow(Docker::Network).to receive(:get).with("bridge").and_return(mock_docker_network)
						allow(mock_docker_network)
							.to receive(:info)
							.and_return(
								"EnableIPv6" => true,
								"IPAM"       => {
									"Driver" => "default",
									"Config" => [
										{
											"Subnet" => "192.0.2.0/24",
											"Gateway" => "192.0.2.1",
										},
									],
								},
							)
					end

					it "raises an appropriate exception" do
						expect { container.run }.to raise_error(MobyDerp::ContainerError)
					end
				end
			end
		end
	end
end
