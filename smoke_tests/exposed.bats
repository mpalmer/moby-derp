load test_helper

@test "Exposed ports" {
	config_file <<-'EOF'
		expose:
		  - 80
		  - "53/udp"
		containers:
		  bob:
		    image: busybox:latest
		    command: sleep 600
		common_labels:
		  moby-derp-smoke-test: ayup
EOF

	run $MOBY_DERP_BIN $TEST_CONFIG_FILE

	echo "status: $status"
	echo "output: $output"

	[ "$status" = "0" ]
	container_running "mdst"
	container_running "mdst.bob"

	docker inspect mdst --format='{{.Config.ExposedPorts}}'
	docker inspect mdst --format='{{.Config.ExposedPorts}}' | grep 'map.*53/udp:{}'
	docker inspect mdst --format='{{.Config.ExposedPorts}}' | grep 'map.*80/tcp:{}'
}
