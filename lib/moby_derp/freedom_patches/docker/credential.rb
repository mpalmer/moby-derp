require "json"
require "open3"
require "pathname"
require "uri"

module Docker
	module Credential
		#:nocov:
		def self.for(ref)
			image_cred(ref)
		end

		private

		def self.image_cred(ref)
			cred_helper = hunt_for_image_domain_cred(ref, docker_config.fetch("credHelpers", {}))

			if cred_helper
				out, rv = Open3.capture2e("docker-credential-#{cred_helper}", "get", stdin_data: image_domain(ref))

				if rv.exitstatus == 0
					cred_data = JSON.parse(out)

					{ username: cred_data["Username"], password: cred_data["Secret"], serveraddress: image_domain(ref) }
				else
					raise RuntimeError, "Credential helper docker-credential-#{cred_helper} exited with #{rv.exitstatus}: #{out}"
				end
			else
				cred = hunt_for_image_domain_cred(ref, docker_config.fetch("auths", {}))

				if cred
					user, pass = JSON.parse(cred.fetch("auth", "null"))&.unpack("m")&.first&.split(":", 2)

					if user && pass
						{ username: user, password: pass, serveraddress: image_domain(ref) }
					else
						{}
					end
				else
					{}
				end
			end
		end

		def self.hunt_for_image_domain_cred(ref, section)
			section.find do |k, v|
				if k =~ /:\/\//
					# Doin' it URL style
					URI(k).host == image_domain(ref)
				else
					k == image_domain(ref)
				end
			end&.last
		end

		def self.image_domain(ref)
			if match_data = ref.match(Docker::Image::IMAGE_REFERENCE)
				if match_data[1] =~ /[.:]/
					match_data[1].gsub(/\/\z/, '')
				else
					"index.docker.io"
				end
			else
				raise ArgumentError, "Could not parse image ref #{ref.inspect}"
			end
		end

		def self.docker_config
			if (f = Pathname.new(ENV.fetch("DOCKER_CONFIG", "~/.docker")).expand_path.join("config.json")).exist?
				JSON.parse(f.read)
			else
				{}
			end
		end

		module ImageClassMixin
			def create(opts = {}, creds = nil, conn = Docker.connection, &block)
				if creds.nil?
					image = opts["fromImage"] || opts[:fromImage]

					creds = Docker::Credential.for(image)
				end

				super(opts, creds, conn, &block)
			end
		end
		#:nocov:
	end
end

Docker::Image.singleton_class.prepend(Docker::Credential::ImageClassMixin)
