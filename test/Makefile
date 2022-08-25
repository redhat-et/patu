# CI infrastructure setup and tests triggered by actions workflow

install-kind:
	./scripts/setup-kind.sh -i $(IP_FAMILY) -b $(BACKEND) -c -n 1

# install-microshift:
# TODO once integrated

# Runs the custom Patu e2e tests
run-e2e:
	cd e2e; \
	go test -timeout=0 -v . \
            -ginkgo.v \
            -provider skeleton \
            -ginkgo.skip=$(GINKGO_SKIP_TESTS) \
            -kubeconfig $(KUBECONFIG)
	cd ..

# Initializes kube conformance tests
run-kube-conformance-e2e:
	./scripts/test-e2e.sh -i $(IP_FAMILY) -b $(BACKEND) -c -n 1
