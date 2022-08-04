# CI infrastructure setup and tests triggered by actions workflow

install-kind:
	./scripts/setup-kind.sh -i $(IP_FAMILY) -b $(BACKEND) -c -n 1

# install-microshift:
# TODO once integrated

run-e2e:
	./scripts/test-e2e.sh -i $(IP_FAMILY) -b $(BACKEND) -c -n 1
	cd e2e; \
	ginkgo -r -v; \
	cd ..
