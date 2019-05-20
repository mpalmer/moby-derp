load test_helper

@test "Core labels" {
	config_file <<-'EOF'
		root_labels:
		  foo: booblee
		containers:
		  bob:
		    image: busybox:latest
		    command: sleep 1
		common_labels:
		  moby-derp-smoke-test: ayup
EOF

	run $MOBY_DERP_BIN $TEST_CONFIG_FILE

	echo "status: $status"
	echo "output: $output"

	[ "$status" = "0" ]
	container_running "mdst"
	container_running "mdst.bob"

	docker inspect mdst --format='{{.Config.Labels}}'
	docker inspect mdst --format='{{.Config.Labels}}' | grep 'map.*foo:booblee'
	! docker inspect mdst.bob --format='{{.Config.Labels}}' | grep 'map.*foo:booblee'
}
