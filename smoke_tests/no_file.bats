load test_helper

@test "No config file specified" {
	run $MOBY_DERP_BIN
	[ "$status" = "1" ]
	[[ "$output" =~ No\ config\ file\ specified ]]
}
