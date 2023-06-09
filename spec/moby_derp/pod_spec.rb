require_relative "../spec_helper"

require "moby_derp/pod"
require "moby_derp/pod_config"
require "moby_derp/system_config"

describe MobyDerp::Pod do
	uses_logger

	let!(:real_new)  { MobyDerp::Container.method(:new) }
	let(:pod_config) { instance_double(MobyDerp::PodConfig) }
	let(:pod)        { MobyDerp::Pod.new(pod_config) }

	let(:mock_docker_container) { instance_double(Docker::Container, "root") }
	let(:mock_docker_network)   { instance_double(Docker::Network) }
	let(:mock_docker_image)     { instance_double(Docker::Image) }

	before(:each) do
		allow(pod_config).to receive(:logger).and_return(logger)
		allow(pod_config).to receive(:network_name).and_return("bridge")
		allow(pod_config).to receive(:common_mounts).and_return([])
		allow(pod_config).to receive(:common_labels).and_return({})
		allow(pod_config).to receive(:root_labels).and_return({})
		allow(pod_config).to receive(:common_environment).and_return({})
		allow(pod_config).to receive(:expose).and_return([])
		allow(pod_config).to receive(:hostname).and_return("test-test")
		allow(Docker::Container).to receive(:get).and_raise(Docker::Error::NotFoundError)
		allow(Docker::Container).to receive(:create).and_return(mock_docker_container)
		allow(mock_docker_container).to receive(:start!).and_return(mock_docker_container)
		allow(mock_docker_container).to receive(:id).and_return("mockdockercontainer")
		allow(Docker::Network).to receive(:get).and_return(mock_docker_network)
		allow(mock_docker_network).to receive(:info).and_return("EnableIPv6" => false)
		allow(Docker::Image).to receive(:create).and_return(mock_docker_image)
		allow(mock_docker_image).to receive(:id).and_return("mockdockerimage")
	end

	describe ".new" do
		it "takes a pod config" do
			expect { MobyDerp::Pod.new(pod_config) }.to_not raise_error
		end
	end

	%i{name common_labels common_mounts common_environment mount_root network_name hostname}.each do |method|
		describe "##{method}" do
			it "takes its value from the pod config" do
				expect(pod_config).to receive(method).and_return("proxy value")
				expect(pod.__send__(method)).to eq("proxy value")
			end
		end
	end

	describe "#root_container_id" do
		it "explodes if called before the root container has run" do
			expect { pod.root_container_id }.to raise_error(MobyDerp::BugError)
		end

		it "provides the root_container_id if all is well" do
			pod.instance_variable_set(:@root_container_id, "abc123")
			expect(pod.root_container_id).to eq("abc123")
		end
	end

	describe "#run" do
		let(:mock_sub_container)  { instance_double(MobyDerp::Container, "sub") }
		let(:mock_system_config)  { instance_double(MobyDerp::SystemConfig) }

		before(:each) do
			allow(pod_config).to receive(:containers).and_return([])
			allow(pod_config).to receive(:system_config).and_return(mock_system_config)

			allow(MobyDerp::Container)
				.to receive(:new) do |**args|
					if args[:root_container]
						real_new.call(**args)
					else
						mock_sub_container
					end
				end

			allow(pod_config).to receive(:name).and_return("mullet")
			allow(pod_config).to receive(:root_labels).and_return("core" => "label!")
			allow(Docker::Container).to receive(:create).and_return(mock_docker_container)
		end

		it "creates the root container appropriately" do
			expect(MobyDerp::Container)
				.to receive(:new) do |pod:, container_config:, root_container:|
					expect(root_container).to eq(true)

					cfg = container_config

					expect(cfg.image).to eq("gcr.io/google_containers/pause-amd64:3.0")
					expect(cfg.update_image).to eq(true)
					expect(cfg.command).to eq([])
					expect(cfg.environment).to eq({})
					expect(cfg.mounts).to eq([])
					expect(cfg.labels).to eq("core" => "label!")
					expect(cfg.readonly).to eq(true)
					expect(cfg.stop_signal).to eq("SIGTERM")
					expect(cfg.stop_timeout).to eq(10)
					expect(cfg.restart).to eq("always")
					expect(cfg.limits).to eq({})

					real_new.call(pod: pod, container_config: container_config, root_container: root_container)
				end

			pod.run
		end

		it "passes the right container name to Moby" do
			expect(Docker::Container).to receive(:create) do |cfg|
				expect(cfg["name"]).to eq("mullet")

				mock_docker_container
			end

			pod.run
		end

		context "when the root container exists and is up-to-date" do
			before(:each) do
				allow(Docker::Container).to receive(:get).with("mullet").and_return(mock_docker_container)
				allow(mock_docker_container).to receive(:id).and_return("mockmockmockid")
				allow(mock_docker_container)
					.to receive(:info)
					.and_return(
						"Config" => {
							"Labels" => {
								"org.hezmatt.moby-derp.config-hash" => "sha256:70fbd77da82ec46680db1b08f000f60b43cd5daa70c92f42032870027d23faf8",
								"org.hezmatt.moby-derp.pod-name"    => "mullet",
							},
						},
						"State" => {
							"Status" => "running",
						},
					)
			end

			it "doesn't restart anything" do
				expect(mock_docker_container).to_not receive(:delete)

				pod.run
			end

			it "stores the root container ID" do
				pod.run

				expect(mock_docker_container).to have_received(:id)
				expect(pod.root_container_id).to eq("mockmockmockid")
			end
		end

		context "with defined containers" do
			let(:mock_container_config) { instance_double(MobyDerp::ContainerConfig) }

			before(:each) do
				allow(pod_config).to receive(:containers).and_return([mock_container_config] * 3)
				allow(mock_container_config).to receive(:name).and_return("bob")
				allow(mock_sub_container).to receive(:run)
			end

			it "runs those containers, too" do
				expect(mock_sub_container).to receive(:run).exactly(3).times

				pod.run
			end

			context "and one of them explodes on the pad" do
				before(:each) do
					allow(mock_sub_container).to receive(:run).and_raise(MobyDerp::ContainerError, "Houston, we've had a problem")
					allow(mock_container_config).to receive(:name).and_return("pod-fun")
				end

				it "logs an exception that tells us which container failed" do
					expect(logger).to receive(:error)
					pod.run
				end
			end

			context "with an existing labelled container that isn't in the pod" do
				before(:each) do
					allow(Docker::Container).to receive(:all).and_return([mock_docker_container])
					allow(mock_docker_container).to receive(:info).and_return(
						"Names" => ["/mullet.gorn"],
						"Labels" => {
							"org.hezmatt.moby-derp.pod-name" => "mullet",
							"org.hezmatt.moby-derp.root-container-id" => "xyzzy123"
						}
					)
					allow(mock_docker_container).to receive(:stop)
					allow(mock_docker_container).to receive(:delete)
				end

				it "asks for a list of all containers" do
					expect(Docker::Container).to receive(:all).with(all: true)

					pod.run
				end

				it "stops and deletes the now-obsolete container" do
					expect(mock_docker_container).to receive(:stop)
					expect(mock_docker_container).to receive(:delete)

					pod.run
				end
			end
		end
	end
end
