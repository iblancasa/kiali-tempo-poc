ISTIO_VERSION ?= "1.17.0"
ISTIO_SHORT_VERSION = "$(shell echo $(ISTIO_VERSION) | grep -oE '[0-9]\.[0-9]+')"

LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

ISTIOCTL ?= $(LOCALBIN)/istioctl
KIND ?= $(LOCALBIN)/kind

# Install kind
.PHONY: kind
kind: $(KIND)
$(KIND): $(LOCALBIN)
	GOBIN=$(LOCALBIN) go install sigs.k8s.io/kind@v0.17.0

# Install istioctl
.PHONY: istioctl
istioctl: $(ISTIOCTL)
$(ISTIOCTL): $(LOCALBIN)
	cd $(LOCALBIN) && curl -sL https://istio.io/downloadIstio | ISTIO_VERSION=$(ISTIO_VERSION) TARGET_ARCH=x86_64 sh -
	mv $(LOCALBIN)/istio-$(ISTIO_VERSION)/bin/istioctl $(LOCALBIN)
	rm -rf $(LOCALBIN)/istio-$(ISTIO_VERSION)

# Start kind cluster
.PHONY: start-kind
start-kind:
	echo "Starting KIND cluster..."
	$(KIND) create cluster --config config/kind.yaml 2>&1 | grep -v "already exists" || true

# Install Istio in the cluster
.PHONY: install-istio
install-istio: istioctl
	$(ISTIOCTL) install --set profile=demo -y

# Install the Prometheus addon
.PHONY: install-prometheus
install-prometheus:
	kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-$(ISTIO_SHORT_VERSION)/samples/addons/prometheus.yaml

# Install the Kiali addon
.PHONY: install-kiali
install-kiali:
	kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-$(ISTIO_SHORT_VERSION)/samples/addons/kiali.yaml

# Uninstall the Kiali addon
.PHONY: uninstall-kiali
uninstall-kiali:
	kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-$(ISTIO_SHORT_VERSION)/samples/addons/kiali.yaml

# Prepare the environment
.PHONY: prepare-env
prepare-env: install-istio
