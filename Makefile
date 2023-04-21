K8S_VERSION = 1.25
ISTIO_VERSION ?= "1.17.0"
ISTIO_SHORT_VERSION = "$(shell echo $(ISTIO_VERSION) | grep -oE '[0-9]\.[0-9]+')"

LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

ISTIOCTL ?= $(LOCALBIN)/istioctl
KIND ?= $(LOCALBIN)/kind
TANKA ?= $(LOCALBIN)/tk
JB ?= $(LOCALBIN)/jb

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

# Install tanka
.PHONY: tanka
tanka: $(TANKA)
$(TANKA): $(LOCALBIN)
	GOBIN=$(LOCALBIN) go install github.com/grafana/tanka/cmd/tk@latest

# Install jb
.PHONY: jb
jb: $(JB)
$(JB): $(LOCALBIN)
	GOBIN=$(LOCALBIN) go install github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb@latest

# Start kind cluster
.PHONY: start-kind
start-kind: kind
	echo "Starting KIND cluster..."
	$(KIND) create cluster --config config/kind.yaml 2>&1 | grep -v "already exists" || true

	kubectl wait --timeout=5m --for=condition=available deployment/coredns -n kube-system

	# Ingress Controller
	kubectl create -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.0.1/deploy/static/provider/kind/deploy.yaml
	kubectl wait --namespace ingress-nginx \
		--for=condition=ready pod \
		--selector=app.kubernetes.io/component=controller \
		--timeout=90s

	# Load balancer
	kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml
	kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=90s
	kubectl apply -f https://kind.sigs.k8s.io/examples/loadbalancer/metallb-config.yaml


# Install Istio in the cluster
.PHONY: install-istio
deploy-istio: istioctl
	$(ISTIOCTL) install --set profile=demo -y --set meshConfig.defaultConfig.tracing.zipkin.address=distributor.tempo.svc.cluster.local:9411

# Install the Prometheus addon
.PHONY: install-prometheus
deploy-prometheus:
	kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-$(ISTIO_SHORT_VERSION)/samples/addons/prometheus.yaml

.PHONY: deploy-kiali
deploy-kiali:
	kubectl apply -f config/kiali.yaml

.PHONY: deploy-prometheus
deploy-prometheus:
	kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-$(ISTIO_SHORT_VERSION)/samples/addons/prometheus.yaml

# Deploy Tempo in the cluster
.PHONY: deploy-tempo
deploy-tempo: tanka jb
	kubectl create namespace tempo 2>&1 | grep -v "already exists" || true
	kubectl apply -f ./config/minio.yaml -n tempo
	PATH=$(PATH):$(LOCALBIN) ./hack/install-tempo.sh
	cd tempo && echo yes | $(TANKA) apply environments/tempo/main.jsonnet

.PHONY: deploy-bookinfo
deploy-bookinfo:
	kubectl label namespace default istio-injection=enabled
	kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-${ISTIO_SHORT_VERSION}/samples/bookinfo/platform/kube/bookinfo.yaml
	kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.17/samples/bookinfo/networking/bookinfo-gateway.yaml
