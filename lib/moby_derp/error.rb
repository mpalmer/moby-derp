module MobyDerp
	# Base class for all MobyDerp-specific errors
	class Error < StandardError; end

	# Raised when something isn't quite right with the system or pod
	# configuration
	class ConfigurationError < Error; end

	# Indicates there was a problem manipulating a live container
	class ContainerError < Error; end

	# Only appears when an inviolable assertion is invalid, and indicates
	# there is a bug in the code
	class BugError < Error; end
end
