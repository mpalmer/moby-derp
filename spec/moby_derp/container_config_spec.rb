require_relative "../spec_helper"

require "moby_derp/container_config"
require "moby_derp/pod_config"
require "moby_derp/system_config"

describe MobyDerp::ContainerConfig do
	let(:system_config) { instance_double(MobyDerp::SystemConfig) }
	let(:pod_config) { instance_double(MobyDerp::PodConfig) }
	let(:container_name) { "bob" }
	let(:base_options) { { image: "bob:latest" } }
	let(:options) { base_options }

	let(:container_config) { MobyDerp::ContainerConfig.new(system_config: system_config, pod_config: pod_config, container_name: container_name, **options) }

	before(:each) do
		allow(system_config).to receive(:cpu_count).and_return(4)
		allow(system_config).to receive(:cpu_bits).and_return(64)
		allow(pod_config).to receive(:mount_root).and_return("/srv/docker")
		allow(pod_config).to receive(:name).and_return("spec-pod")
	end

	it "needs certain minimum parameters" do
		expect { MobyDerp::ContainerConfig.new(system_config: system_config, pod_config: pod_config, container_name: "bob", image: "bob:latest") }.to_not raise_error
		expect { MobyDerp::ContainerConfig.new(pod_config: pod_config, container_name: "bob", image: "bob:latest") }.to raise_error(ArgumentError)
		expect { MobyDerp::ContainerConfig.new(system_config: system_config, container_name: "bob", image: "bob:latest") }.to raise_error(ArgumentError)
		expect { MobyDerp::ContainerConfig.new(system_config: system_config, pod_config: pod_config, image: "bob:latest") }.to raise_error(ArgumentError)
		expect { MobyDerp::ContainerConfig.new(system_config: system_config, pod_config: pod_config, container_name: "bob") }.to raise_error(ArgumentError)
	end

	describe "#name" do
		it "returns the fully-qualified container name" do
			expect(container_config.name).to eq("spec-pod.bob")
		end
	end

	{
		"image is not a string" =>
			{ image: 42 },
		"image reference is invalid" =>
			{ image: "foo bar" },

		"update_image isn't boolean" =>
			{ update_image: "sure, ok" },

		"command isn't a string or array" =>
			{ command: { "foo" => "bar" } },
		"element of command array isn't a string" =>
			{ command: ["foo", "bar", 42] },

		"entrypoint isn't a string" =>
			{ entrypoint: ["foo", "bar"] },

		"environment isn't a hash" =>
			{ environment: "rainforest" },
		"environment contains non-string key" =>
			{ environment: { 42 =>"the answer" } },
		"environment contains non-string value" =>
			{ environment: { "the answer" => 42 } },
		"environment key contains an equals sign" =>
			{ environment: { "one=two" => "naaaah" } },

		"mounts isn't an array" =>
			{ mounts: "horse" },
		"an invalid key in a common mount declaration" =>
			{ mounts: [{ "source" => "X", "target" => "/X", "blah" => "flingle" }] },
		"missing a required keyword in a common mount declaration" =>
			{ mounts: [{ "source" => "xyzzy" }] },
		"a mount source keyword value isn't a string" =>
			{ mounts: [{ "source" => %w{catsup mustard}, "target" => "/foo" }] },
		"a mount source keyword value is traversing upward" =>
			{ mounts: [{ "source" => "../../../../etc/passwd", "target" => "/foo" }] },
		"a mount source keyword value is sneakily traversing upward" =>
			{ mounts: [{ "source" => "foo/../../../../etc/passwd", "target" => "/foo" }] },
		"a mount source keyword value is trying to pop a homedir" =>
			{ mounts: [{ "source" => "~bob", "target" => "/foo" }] },
		"a mount source keyword value is an absolute path" =>
			{ mounts: [{ "source" => "/etc/passwd", "target" => "/foo" }] },
		"a mount target keyword value isn't a string" =>
			{ mounts: [{ "source" => "foo", "target" => %w{archery bullseye} }] },
		"a mount target is a relative path" =>
			{ mounts: [{ "source" => "foo", "target" => "foo" }] },
		"a mount target contains traversal" =>
			{ mounts: [{ "source" => "foo", "target" => "/foo/../bar" }] },
		"a readonly flag isn't a boolean" =>
			{ mounts: [{ "source" => "foo", "target" => "/foo", "readonly" => "maybe" }] },

		"labels isn't a hash" =>
			{ labels: "records" },
		"labels contains non-string key" =>
			{ labels: { 42 =>"the answer" } },
		"labels contains non-string value" =>
			{ labels: { "the answer" => 42 } },

		"readonly isn't boolean" =>
			{ readonly: "not on your life, bucko" },

		"stop_signal isn't string or integer" =>
			{ stop_signal: ["traffic", "lights"] },
		"stop_signal is invalid signal number" =>
			{ stop_signal: 9001 },
		"stop_signal is invalid signal string" =>
			{ stop_signal: "FLIBBETS" },

		"stop_timeout isn't a number" =>
			{ stop_timeout: "whenever you've got a moment" },
		"stop_timeout is negative" =>
			{ stop_timeout: -42 },

		"user spec isn't a string" =>
			{ user: { "uid" => 42, "gid" => 31337 } },
		"user spec doesn't match the required format" =>
			{ user: "something funny" },

		"restart isn't a string" =>
			{ restart: { "on-failure" => 42 } },
		"restart isn't a recognised string" =>
			{ restart: "whenever something goes right" },

		"limits isn't a hash" =>
			{ limits: "none" },
		"limits includes unrecognised key" =>
			{ limits: { "max-speed" => 299_792_458 } },

		"limits.cpus isn't a number" =>
			{ limits: { "cpus" => "all of 'em" } },
		"limits.cpus is zero" =>
			{ limits: { "cpus" => 0 } },
		"limits.cpus is negative" =>
			{ limits: { "cpus" => -0.5 } },
		"limits.cpus is greater than system CPU count" =>
			{ limits: { "cpus" => 9001 } },

		"limits.cpu-shares isn't a number" =>
			{ limits: { "cpu-shares" => "all of 'em" } },
		"limits.cpu-shares isn't an integer" =>
			{ limits: { "cpu-shares" => 500.25 } },
		"limits.cpu-shares is less than the minimum" =>
			{ limits: { "cpu-shares" => 1 } },
		"limits.cpu-shares is greater than the default" =>
			{ limits: { "cpu-shares" => 1025 } },

		"limits.memory isn't a number or string" =>
			{ limits: { "memory" => true } },
		"limits.memory isn't an integer" =>
			{ limits: { "memory" => 500.25 } },
		"limits.memory is negative" =>
			{ limits: { "memory" => -100 } },
		"limits.memory uses an invalid suffix" =>
			{ limits: { "memory" => "9001z" } },

		"limits.memory-swap isn't a number or string" =>
			{ limits: { "memory-swap" => true } },
		"limits.memory-swap isn't an integer" =>
			{ limits: { "memory-swap" => 500.25 } },
		"limits.memory-swap is negative" =>
			{ limits: { "memory-swap" => -100 } },
		"limits.memory-swap uses an invalid suffix" =>
			{ limits: { "memory-swap" => "9001z" } },

		"limits.memory-reservation isn't a number or string" =>
			{ limits: { "memory-reservation" => true } },
		"limits.memory-reservation isn't an integer" =>
			{ limits: { "memory-reservation" => 500.25 } },
		"limits.memory-reservation is negative" =>
			{ limits: { "memory-reservation" => -100 } },
		"limits.memory-reservation uses an invalid suffix" =>
			{ limits: { "memory-reservation" => "9001z" } },

		"limits.oom-score-adj isn't a number" =>
			{ limits: { "oom-score-adj" => "never!" } },
		"limits.oom-score-adj isn't an integer" =>
			{ limits: { "oom-score-adj" => 500.25 } },
		"limits.oom-score-adj is negative" =>
			{ limits: { "oom-score-adj" => -100 } },
		"limits.oom-score-adj is greater than the maximum" =>
			{ limits: { "oom-score-adj" => 1001 } },

		"limits.pids isn't a number" =>
			{ limits: { "pids" => "many many many" } },
		"limits.pids isn't an integer" =>
			{ limits: { "pids" => 500.25 } },
		"limits.pids is negative" =>
			{ limits: { "pids" => -100 } },
		"limits.pids is greater than the maximum" =>
			{ limits: { "pids" => 4194305 } },

		"limits.shm-size isn't a number or string" =>
			{ limits: { "shm-size" => true } },
		"limits.shm-size isn't an integer" =>
			{ limits: { "shm-size" => 500.25 } },
		"limits.shm-size is negative" =>
			{ limits: { "shm-size" => -100 } },
		"limits.shm-size uses an invalid suffix" =>
			{ limits: { "shm-size" => "9001z" } },

		"health check isn't a hash" =>
			{ startup_health_check: "/usr/bin/false" },
		"health check command is missing" =>
			{ startup_health_check: {} },
		"health check command isn't a string or array" =>
			{ startup_health_check: { command: { "foo" => "bar" } } },
		"element of health check command array isn't a string" =>
			{ startup_health_check: { command: ["foo", "bar", 42] } },
		"health check interval isn't a number" =>
			{ startup_health_check: { command: "bob", interval: "whatever" } },
		"health check interval is negative" =>
			{ startup_health_check: { command: "bob", interval: -42 } },
		"health check attempts isn't a number" =>
			{ startup_health_check: { command: "bob", attempts: "infinite" } },
		"health check attempts isn't an integer" =>
			{ startup_health_check: { command: "bob", attempts: 3.14159625 } },
		"health check attempts is zero" =>
			{ startup_health_check: { command: "bob", attempts: 0 } },
		"health check attempts is negative" =>
			{ startup_health_check: { command: "bob", attempts: -42 } },

	}.each do |desc, opts|
		context "when #{desc}" do
			let(:options) { base_options.merge(opts) }

			it "raises an appropriate exception" do
				expect { container_config }.to raise_error(MobyDerp::ConfigurationError)
			end
		end
	end

	context "on a 32-bit platform" do
		before(:each) do
			allow(system_config).to receive(:cpu_bits).and_return(32)
		end

		let(:options) { base_options.merge(limits: { "pids" => 32769 }) }

		it "limits pids to 32768" do
			expect { container_config }.to raise_error(MobyDerp::ConfigurationError)
		end
	end

	%w{core cpu data fsize memlock msgqueue nofile rttime stack}.each do |ulimit|
		{
			"not a string or number" => [42, 64],
			"negative" => -42,
			"an unparseable string" => "all of them!",
		}.each do |desc, value|
			context "when ulimit-#{ulimit} is #{desc}" do
				let(:options) { base_options.merge(limits: { "ulimit-#{ulimit}" => value }) }

				it "raises an appropriate exception" do
					expect { container_config }.to raise_error(MobyDerp::ConfigurationError)
				end
			end
		end
	end
end
