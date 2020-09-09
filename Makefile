default:
	@echo "please choose a make target..."

release:
	@echo "Checking that VERSION was defined in the calling environment"
	@test -n "$(VERSION)"
	@echo "OK.  VERSION=$(VERSION)"
	bosh create-release --final --tarball=releases/ipsec-$(VERSION).tgz --name ipsec --version $(VERSION)
	git add releases/ipsec .final_builds
	git commit -m "Release v$(VERSION)"
	git tag v$(VERSION)

yaml-snippet:
	@echo >&2 "Checking that VERSION was defined in the calling environment"
	@test -n "$(VERSION)"
	@echo >&2 "OK.  VERSION=$(VERSION)"
	@echo "releases:"
	@echo "  - name:    ipsec"
	@echo "    version: $(VERSION)"
	@echo "    url:     https://github.com/jhunt/ipsec-boshrelease/releases/download/v$(VERSION)/ipsec-$(VERSION).tgz"
	@echo "    sha1:    $(shell sha1sum releases/ipsec-$(VERSION).tgz | awk '{print $$1}')"
	@echo
