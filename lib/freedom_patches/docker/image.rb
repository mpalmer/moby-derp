module Docker
	class Image
		# https://github.com/docker/distribution/blob/master/reference/reference.go
		# as at 2019-04-23
		DIGEST_HEX                 = /[0-9a-fA-F]{32,}/
		DIGEST_ALGORITHM_COMPONENT = /[A-Za-z][A-Za-z0-9]*/
		DIGEST_ALGORITHM_SEPARATOR = /[+._-]/
		DIGEST_ALGORITHM           = /#{DIGEST_ALGORITHM_COMPONENT}(#{DIGEST_ALGORITHM_SEPARATOR}#{DIGEST_ALGORITHM_COMPONENT})*/
		DIGEST                     = /#{DIGEST_ALGORITHM}:#{DIGEST_HEX}/

		TAG = /[\w][\w.-]{0,127}/

		SEPARATOR        = /[_.]|__|[-]*/
		ALPHANUMERIC     = /[a-z0-9]+/
		PATH_COMPONENT   = /#{ALPHANUMERIC}(#{SEPARATOR}#{ALPHANUMERIC})*/
		PORT_NUMBER      = /\d+/
		DOMAIN_COMPONENT = /([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9])/
		DOMAIN           = /#{DOMAIN_COMPONENT}(\.#{DOMAIN_COMPONENT})*(:#{PORT_NUMBER})?/
		NAME             = /(#{DOMAIN}\/)?#{PATH_COMPONENT}(\/#{PATH_COMPONENT})*/
		IMAGE_REFERENCE  = /\A#{NAME}(:#{TAG})?(@#{DIGEST})?\z/
	end
end

