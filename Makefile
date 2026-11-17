.PHONY: test install
test:
	bash test/knockout-test.sh
	bin/knockout

install:
	./install.sh
