load test_helper

@test "Restart always" {
	config_file <<-'EOF'
		containers:
		  bob:
		    image: busybox:latest
		    command: sleep 600
		    restart: always
		common_labels:
		  moby-derp-smoke-test: ayup
EOF

	run $MOBY_DERP_BIN $TEST_CONFIG_FILE

	[ "$status" = "0" ]

	docker stop mdst.bob
	run $MOBY_DERP_BIN $TEST_CONFIG_FILE

	echo $output
	container_running "mdst"
	container_running "mdst.bob"
}
