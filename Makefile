KIND ?= $(LOCALBIN)/kind

# Start kind cluster
.PHONY: start-kind
start-kind:
	echo "Starting KIND cluster..."
	kind create cluster --config config/kind.yaml 2>&1 | grep -v "already exists" || true
