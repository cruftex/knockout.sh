.PHONY: test install
test:
	bash test/knockout_test.sh
	bin/knockout test/ examples/

install:
	./install.sh
