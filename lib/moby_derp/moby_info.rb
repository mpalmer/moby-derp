module MobyDerp
	class MobyInfo
		attr_reader :cpu_count, :cpu_bits

		def initialize(info)
			@cpu_count = info["NCPU"]
			# As far as I can tell, the only 32-bit platform Moby supports is
			# armhf; if that turns out to be incorrect, amend the list below.
			@cpu_bits  = %w{armhf}.include?(info["Architecture"]) ? 32 : 64
		end
	end
end
