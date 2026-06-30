.PHONY: run test build clean

SWIFT_SCRATCH_PATH ?= /tmp/CoLearner-build
SWIFT_TEST_SCRATCH_PATH ?= /tmp/CoLearner-test-build

run:
	COLEARNER_SWIFT_SCRATCH_PATH="$(SWIFT_SCRATCH_PATH)" scripts/run-dev.sh

test:
	swift test --scratch-path "$(SWIFT_TEST_SCRATCH_PATH)"

build:
	swift build --scratch-path "$(SWIFT_SCRATCH_PATH)"

clean:
	rm -rf "$(SWIFT_SCRATCH_PATH)" "$(SWIFT_TEST_SCRATCH_PATH)" /tmp/CoLearner.app .build
