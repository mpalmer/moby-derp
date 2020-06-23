require_relative "../spec_helper"

require "moby_derp/pod_config"
require "moby_derp/system_config"

describe MobyDerp::PodConfig do
	uses_logger

	let(:config_filename) { "./my-pod.yaml" }
	let(:minimal_config) { { "containers" => { "bob" => { "image" => "bob" } } } }
	let(:full_config) do
		{
			"containers" => {
				"one" => {
					"image" => "foo/one:latest",
				},
				"two" => {
					"image" => "foo/two:latest",
				},
			},
			"hostname" => "custom-hostname",
			"common_environment" => {
				"FRED" => "yabba dabba",
				"BARNEY" => "doo!",
			},
			"common_labels" => {
				"com.example.demo-label" => "something",
			},
			"root_labels" => {
				"com.example.sd_label" => "over here",
			},
			"common_mounts" => [
				{ "source" => "faff", "target" => "/srv/faff" },
				{ "source" => "assets/faff", "target" => "/srv/faff/public", "readonly" => true },
			],
			"expose"  => [80, "443", "53/udp"],
			"publish" => [":80", ":443", ":53/udp"],
			"publish_all" => true,
		}
	end

	let(:config)               { {} }
	let(:config_file_contents) { config.to_yaml }

	let(:system_config) { instance_double(MobyDerp::SystemConfig) }

	let(:pod_config) { MobyDerp::PodConfig.new(config_filename, system_config) }

	before(:each) do
		allow(File).to receive(:read)
		allow(File).to receive(:read).with(config_filename).and_return(config_file_contents)
		allow(system_config).to receive(:mount_root).and_return("/srv/docker")
		allow(system_config).to receive(:port_whitelist).and_return({})
		allow(system_config).to receive(:network_name).and_return("CBS")
		allow(system_config).to receive(:use_host_resolv_conf).and_return(false)
		allow(system_config).to receive(:logger).and_return(logger)
	end

	describe "#network_name" do
		let(:config) { minimal_config }

		it "takes the value from the system config" do
			expect(system_config).to receive(:network_name).and_return("freddy")
			expect(pod_config.network_name).to eq("freddy")
		end
	end

	context "no config" do
		let(:config) { {} }

		it "raises a relevant exception" do
			expect { pod_config }.to raise_error(MobyDerp::ConfigurationError)
		end
	end

	context "minimal config" do
		let(:config) { minimal_config }

		it "sets the pod's name from the filename" do
			expect(pod_config.name).to eq("my-pod")
		end

		it "loads up the containers list" do
			expect(pod_config.containers).to be_a(Array)
			expect(pod_config.containers.length).to eq(1)
			expect(pod_config.containers.first.name).to eq("my-pod.bob")
		end

		it "sets a default hostname" do
			expect(Socket).to receive(:gethostname).and_return("speccy")

			expect(pod_config.hostname).to eq("my-pod-speccy")
		end

		%i{common_environment common_labels root_labels}.each do |hash_opt|
			it "sets a default for #{hash_opt}" do
				expect(pod_config.__send__(hash_opt)).to eq({})
			end
		end

		%i{common_mounts expose publish}.each do |array_opt|
			it "sets a default for #{array_opt}" do
				expect(pod_config.__send__(array_opt)).to eq([])
			end
		end

		it "sets a default for publish_all" do
			expect(pod_config.publish_all).to eq(false)
		end

		it "sets a default for mount_root" do
			expect(pod_config.mount_root).to eq("/srv/docker/my-pod")
		end
	end

	context "when the pod name contains an underscore" do
		let(:config) { minimal_config }
		let(:config_filename) { "./my_pod.yml" }

		it "translates the hostname to have a hyphen instead" do
			expect(Socket).to receive(:gethostname).and_return("speccy")

			expect(pod_config.hostname).to eq("my-pod-speccy")
		end

		it "leaves the pod name itself alone" do
			expect(pod_config.name).to eq("my_pod")
		end

		it "leaves the mount root alone" do
			expect(pod_config.mount_root).to eq("/srv/docker/my_pod")
		end
	end

	context "when the pod name is invalid" do
		let(:config) { minimal_config }
		let(:config_filename) { "./_podz.yaml" }

		it "raises a relevant exception" do
			expect { pod_config }.to raise_error(MobyDerp::ConfigurationError)
		end
	end

	context "full config" do
		let(:config) { full_config }

		it "accepts a filename and a system config" do
			expect { MobyDerp::PodConfig.new(config_filename, system_config) }.to_not raise_error
		end

		it "reads from the specified file" do
			pod_config

			expect(File).to have_received(:read).with("./my-pod.yaml")
		end

		it "uses the custom-set hostname" do
			expect(pod_config.hostname).to eq("custom-hostname")
		end

		it "stores the containers" do
			expect(pod_config.containers).to be_a(Array)
			expect(pod_config.containers.all? { |c| MobyDerp::ContainerConfig === c }).to be(true)
			expect(pod_config.containers.map(&:name)).to include("my-pod.one", "my-pod.two")
		end

		it "stores the common environment" do
			expect(pod_config.common_environment).to eq("FRED" => "yabba dabba", "BARNEY" => "doo!")
		end

		it "stores the common labels" do
			expect(pod_config.common_labels).to eq("com.example.demo-label" => "something")
		end

		it "stores the root labels" do
			expect(pod_config.root_labels).to eq("com.example.sd_label" => "over here")
		end

		it "stores the common mounts" do
			expect(pod_config.common_mounts).to be_an(Array)
			expect(pod_config.common_mounts.all? { |m| m.is_a?(MobyDerp::Mount) }).to be(true)
			expect(pod_config.common_mounts.first.source).to eq("faff")
			expect(pod_config.common_mounts.first.target).to eq("/srv/faff")
			expect(pod_config.common_mounts.first.readonly).to eq(false)

			expect(pod_config.common_mounts.last.source).to eq("assets/faff")
			expect(pod_config.common_mounts.last.target).to eq("/srv/faff/public")
			expect(pod_config.common_mounts.last.readonly).to eq(true)
		end

		it "stores the exposed ports" do
			expect(pod_config.expose).to eq(["80/tcp", "443/tcp", "53/udp"])
		end

		it "stores the published ports" do
			expect(pod_config.publish).to eq([":80", ":443", ":53/udp"])
		end

		it "stores the publish_all setting" do
			expect(pod_config.publish_all).to eq(true)
		end
	end

	%i{common_environment common_labels root_labels}.each do |hash_opt|
		context "when #{hash_opt} is not a hash" do
			let(:config) { minimal_config.merge(hash_opt.to_s => "something funny") }

			it "raises a relevant exception" do
				expect { pod_config }.to raise_error(MobyDerp::ConfigurationError)
			end
		end

		context "when #{hash_opt} contains a non-string key" do
			let(:config) { minimal_config.merge(hash_opt.to_s => { 42 => "the answer" }) }

			it "raises a relevant exception" do
				expect { pod_config }.to raise_error(MobyDerp::ConfigurationError)
			end
		end

		context "when #{hash_opt} contains a non-string value" do
			let(:config) { minimal_config.merge(hash_opt.to_s => { "faff" => %w{one two} }) }

			it "raises a relevant exception" do
				expect { pod_config }.to raise_error(MobyDerp::ConfigurationError)
			end
		end
	end

	{
		"containers is not a hash" =>
			{ "containers" => "tupperware" },
		"container spec is not a hash" =>
			{ "containers" => { "image" => "something/funny" } },
		"a container name is invalid" =>
			{ "containers" => { "a.b.c" => { "image" => "foo" } } },
		"container spec is missing required keyword" =>
			{ "containers" => { "bob" => {} } },
		"container spec has invalid keyword" =>
			{ "containers" => { "bob" => { "image" => "foo", "flibbety" => "gibbets" } } },

		"common_environment has an env var with an equals sign" =>
			{ "common_environment" => { "P=NP" => "yah right" } },

		"common_mounts isn't an array" =>
			{ "common_mounts" => "horse" },
		"an invalid key in a common mount declaration" =>
			{ "common_mounts" => [{ "source" => "X", "target" => "/X", "blah" => "flingle" }] },
		"missing a required keyword in a common mount declaration" =>
			{ "common_mounts" => [{ "source" => "xyzzy" }] },
		"a mount source keyword value isn't a string" =>
			{ "common_mounts" => [{ "source" => %w{catsup mustard}, "target" => "/foo" }] },
		"a mount source keyword value is traversing upward" =>
			{ "common_mounts" => [{ "source" => "../../../../etc/passwd", "target" => "/foo" }] },
		"a mount source keyword value is sneakily traversing upward" =>
			{ "common_mounts" => [{ "source" => "foo/../../../../etc/passwd", "target" => "/foo" }] },
		"a mount source keyword value is trying to pop a homedir" =>
			{ "common_mounts" => [{ "source" => "~bob", "target" => "/foo" }] },
		"a mount source keyword value is an absolute path" =>
			{ "common_mounts" => [{ "source" => "/etc/passwd", "target" => "/foo" }] },
		"a mount target keyword value isn't a string" =>
			{ "common_mounts" => [{ "source" => "foo", "target" => %w{archery bullseye} }] },
		"a mount target is a relative path" =>
			{ "common_mounts" => [{ "source" => "foo", "target" => "foo" }] },
		"a mount target contains traversal" =>
			{ "common_mounts" => [{ "source" => "foo", "target" => "/foo/../bar" }] },
		"a readonly flag isn't a boolean" =>
			{ "common_mounts" => [{ "source" => "foo", "target" => "/foo", "readonly" => "maybe" }] },

		"expose isn't an array" =>
			{ "expose" => "greed and corruption" },
		"an exposed port isn't a number" =>
			{ "expose" => ["port eighty"] },
		"an exposed port number is too small" =>
			{ "expose" => [0] },
		"an exposed port number is negative(?!?)" =>
			{ "expose" => [-42] },
		"an exposed port number is too large" =>
			{ "expose" => [9000000001] },

		"publish isn't an array" =>
			{ "publish" => "a book" },
		"publish spec isn't a string" =>
			{ "publish" => [42] },
		"publish spec is some rando string" =>
			{ "publish" => ["war and peace"] },
		"publish spec is for a specific host port" =>
			{ "publish" => ["80:80"] },
		"publish spec is for an out-of-range port" =>
			{ "publish" => [":9000000001"] },

		"publish_all isn't a boolean" =>
			{ "publish_all" => "yes please" },

		"there is an invalid top-level key" =>
			{ "flibbety" => "gibbets" },
	}.each do |desc, snippet|
		context "when #{desc}" do
			let(:config) { full_config.merge(snippet) }

			it "raises a relevant exception" do
				expect { pod_config }.to raise_error(MobyDerp::ConfigurationError)
			end
		end
	end

	context "with a suitable port whitelist" do
		before(:each) do
			allow(system_config).to receive(:port_whitelist).and_return("80" => "my-pod")
		end

		let(:config) { minimal_config.merge("publish" => ["80:80"]) }

		it "allows the configuration" do
			expect { pod_config }.to_not raise_error
		end
	end

	context "when use_host_resolv_conf is true" do
		let(:config) { minimal_config }
		before(:each) do
			allow(system_config).to receive(:use_host_resolv_conf).and_return(true)
		end

		it "includes a common mount for /etc/resolv.conf" do
			expect(pod_config.common_mounts.length).to eq(1)
			mount = pod_config.common_mounts.first
			expect(mount.source).to eq("/etc/resolv.conf")
			expect(mount.target).to eq("/etc/resolv.conf")
			expect(mount.readonly).to eq(true)
		end
	end

	context "when the specified config file doesn't exist" do
		it "raises a relevant exception" do
			expect(File).to receive(:read).and_raise(Errno::ENOENT)

			expect { MobyDerp::PodConfig.new("/enoent", system_config) }.to raise_error(MobyDerp::ConfigurationError)
		end
	end

	context "when the specified config file isn't readable" do
		it "raises a relevant exception" do
			expect(File).to receive(:read).and_raise(Errno::EPERM)

			expect { MobyDerp::PodConfig.new("/eperm", system_config) }.to raise_error(MobyDerp::ConfigurationError)
		end
	end

	context "when the specified config file isn't valid YAML" do
		let(:config_file_contents) { "mount_root: :" }

		it "raises a relevant exception" do
			expect { MobyDerp::PodConfig.new(config_filename, system_config) }.to raise_error(MobyDerp::ConfigurationError)
		end
	end

	context "when the specified config file isn't a YAML hash" do
		let(:config_file_contents) { "42.5" }

		it "raises a relevant exception" do
			expect { MobyDerp::PodConfig.new(config_filename, system_config) }.to raise_error(MobyDerp::ConfigurationError)
		end
	end
end
