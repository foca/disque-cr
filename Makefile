DEPS = shard.lock src/disque/version.cr
VERSION = $(shell cat shard.yml | sed -n -e '/^version:/s/version: //p')

.PHONY: all
all: $(DEPS) test

.PHONY: test
test: $(DEPS)
	crystal spec

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
