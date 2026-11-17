.PHONY: test install
test:
	bash test/knockout_test.sh
	bin/knockout

install:
	./install.sh
