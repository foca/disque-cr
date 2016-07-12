DEPS = shard.lock src/disque/version.cr
VERSION = $(shell cat shard.yml | sed -n -e '/^version:/s/version: //p')

SERVERS = 6610 6611
TEST_DEPS = $(addprefix tmp/, $(addsuffix /disque.pid, $(SERVERS)))

TEST_PASSWORD = testpass

.PHONY: all
all: $(DEPS) test

.PHONY: test
test: $(DEPS) pre-test
	crystal spec
	$(MAKE) clean-test

.PHONY: pre-test
pre-test: $(TEST_DEPS)
	 for port in $(SERVERS); do $(foreach port,$(SERVERS), disque -a $(TEST_PASSWORD) -p $$port cluster meet 127.0.0.1 $(port);) done >/dev/null

.PHONY: clean-test
clean-test:
	for file in $(TEST_DEPS); do [ -f "$$file" ] && kill `cat $$file`; done
	rm -rf tmp/*/*

.PHONY: release
release: $(DEPS)
	git tag v$(VERSION)
	git push --tags

src/disque/version.cr: shard.yml
	echo 'class Disque' > $@
	echo '  VERSION = "$(VERSION)"' >> $@
	echo 'end' >> $@

shard.lock: shard.yml
	crystal deps

tmp/%/disque.pid: spec/support/disque.tpl | tmp/%
	m4 -DPWD=$(PWD)/tmp/$* -DPORT=$* -DPASSWORD=$(TEST_PASSWORD) $< | disque-server -

tmp $(addprefix tmp/,$(SERVERS)):
	mkdir -p $@
