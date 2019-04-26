load test_helper

@test "Minimal pod creation" {
	config_file <<-'EOF'
		containers:
		  bob:
		    image: busybox:latest
		    command: sleep 600
		common_labels:
		  moby-derp-smoke-test: ayup
EOF

	run $MOBY_DERP_BIN $TEST_CONFIG_FILE

	[ "$status" = "0" ]
	container_running "mdst"
	container_running "mdst.bob"
}
