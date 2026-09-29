# Swift Testing ships with Command Line Tools but isn't on the default search paths there.
CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
ifeq ($(shell xcode-select -p),/Library/Developer/CommandLineTools)
TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT_DEV)/Frameworks \
	-Xlinker -F -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib
endif

.PHONY: build test test-routing test-speech app run check-portable

build:
	swift build

# make test               – all tests (model/speech tests skip themselves)
# make test FILTER=Name   – only tests whose name matches
test:
	swift test $(TEST_FLAGS) $(if $(FILTER),--filter $(FILTER))

test-routing:
	RELAY_ROUTING_TESTS=1 swift test $(TEST_FLAGS) --filter RoutingModelTests

test-speech:
	RELAY_SPEECH_TESTS=1 swift test $(TEST_FLAGS) --filter SpeechTranscriptionTests

app:
	scripts/make-app.sh

run: app
	open build/Relay.app

check-portable: app
	scripts/check-portable.sh
