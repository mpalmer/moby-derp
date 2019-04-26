: "${MOBY_DERP_BIN:=$BATS_TEST_DIRNAME/../bin/moby-derp}"

config_file() {
	TEST_CONFIG_FILE="$BATS_TMPDIR/mdst.yml"
	cat >"${BATS_TMPDIR}/mdst.yml"
}

container_running() {
	[ "$(docker container inspect "$1" --format='{{.State.Running}}')" = "true" ]
}

setup() {
	TEST_SYSTEM_CONFIG_FILE="$BATS_TMPDIR/moby_derp_system_config.yml"
	mkdir -p $BATS_TMPDIR/docker

	cat <<EOF >"$TEST_SYSTEM_CONFIG_FILE"
mount_root: $BATS_TMPDIR/docker
EOF

	export MOBY_DERP_SYSTEM_CONFIG_FILE="$TEST_SYSTEM_CONFIG_FILE"
}

teardown() {
	for i in $(docker ps -a --format='{{.Names}}'); do
		if docker container inspect $i --format='{{.Config.Labels}}' | grep -q moby-derp-smoke-test; then
			docker rm -f $i
		fi
	done
}
