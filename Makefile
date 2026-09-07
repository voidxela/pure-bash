.PHONY: test lint

test:
	bash -n pure.bash tests/test.sh
	bash tests/test.sh

lint:
	shellcheck pure.bash tests/test.sh
