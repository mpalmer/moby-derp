require_relative "../spec_helper"

require "moby_derp/system_config"

describe MobyDerp::SystemConfig do
	uses_logger

	let(:config_filename)      { "/some/config/file" }
	let(:config_file_contents) { "mount_root: /tmp" }
	let(:moby_info)            { { "NCPU" => 1, "Architecture" => "x86_64" } }

	before(:each) do
		allow(File).to receive(:read)
		allow(File).to receive(:read).with(config_filename).and_return(config_file_contents)
	end

	it "accepts a filename" do
		expect { MobyDerp::SystemConfig.new(config_filename, moby_info, logger) }.to_not raise_error
	end

	it "reads from the specified file" do
		MobyDerp::SystemConfig.new(config_filename, moby_info, logger)

		expect(File).to have_received(:read).with("/some/config/file")
	end

	it "sets the mount_root config variable" do
		expect(MobyDerp::SystemConfig.new(config_filename, moby_info, logger).mount_root).to eq("/tmp")
	end

	it "sets a default for the port whitelist" do
		expect(MobyDerp::SystemConfig.new(config_filename, moby_info, logger).port_whitelist).to eq({})
	end

	it "sets a default for the network name" do
		expect(MobyDerp::SystemConfig.new(config_filename, moby_info, logger).network_name).to eq("bridge")
	end

	context "with a port whitelist" do
		let(:config_file_contents) { "mount_root: /tmp\nport_whitelist:\n  80: some-pod\n  443: some-pod" }

		it "sets the port whitelist" do
		  expect(MobyDerp::SystemConfig.new(config_filename, moby_info, logger).port_whitelist).to eq({ "80" => "some-pod", "443" => "some-pod" })
		end
	end

	context "with a custom network name" do
		let(:config_file_contents) { "mount_root: /tmp\nnetwork_name: bobby" }

		it "sets the network name" do
		  expect(MobyDerp::SystemConfig.new(config_filename, moby_info, logger).network_name).to eq("bobby")
		end
	end

	context "when the specified config file doesn't exist" do
		it "raises a relevant exception" do
			expect(File).to receive(:read).and_raise(Errno::ENOENT)

			expect { MobyDerp::SystemConfig.new("/enoent", moby_info, logger) }.to raise_error(MobyDerp::ConfigurationError)
		end
	end

	context "when the specified config file isn't readable" do
		it "raises a relevant exception" do
			expect(File).to receive(:read).and_raise(Errno::EPERM)

			expect { MobyDerp::SystemConfig.new("/eperm", moby_info, logger) }.to raise_error(MobyDerp::ConfigurationError)
		end
	end

	{
		"the specified config file isn't valid YAML" =>
			"mount_root: :",
		"when the specified config file doesn't have a mount_root key" =>
			"something: funny",
		"when the specified config file doesn't have a string for the mount_root" =>
			"mount_root:\n- one\n- two",
		"when the mount_root specified in the config file isn't an absolute path" =>
			"mount_root: relative/path",
		"when the mount_root specified in the config file doesn't exist" =>
			"mount_root: /this/directory/hopefully/doesnt/exist",
		"when the specified config file isn't a YAML hash" =>
			"42.5",
		"when network_name isn't a string" =>
			"mount_root: /tmp\nnetwork_name:\n- one\n",
	}.each do |desc, config|
		context "when #{desc}" do
			let(:config_file_contents) { config }

			it "raises a relevant exception" do
				expect { MobyDerp::SystemConfig.new(config_filename, moby_info, logger) }.to raise_error(MobyDerp::ConfigurationError)
			end
		end
	end

end
