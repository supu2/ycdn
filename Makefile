PROJECT := $(shell basename $(CURDIR))
current_dir = $(shell pwd)
BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
HASH := $(shell git rev-parse HEAD)
NAMESPACE := $(PROJECT)-$(BRANCH)
ifdef REGISTRY
REGISTRY := $(REGISTRY)
else
REGISTRY := localhost:5001
endif
BREGISTRY := http://192.168.122.1:8000

# HELP
# This will output the help for each task
.PHONY: help

help: ## This help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help

binfolder:
	mkdir -p $(HOME)/.local/bin/
	cat $(HOME)/.bashrc  | grep -qF ".local/bin/"  || echo 'export PATH=$$PATH:$$HOME/.local/bin/' >> $(HOME)/.bashrc 

install-kubectl: binfolder ## Install kubectl 
	curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
	chmod +x kubectl && mv kubectl $(HOME)/.local/bin/kubectl
install-helm: binfolder ## Install helm
	curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
install-kind: binfolder ## kind minimal kubernetes for local development
	curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.14.0/kind-linux-amd64 ;\
	chmod +x ./kind ;\
	mv ./kind $(HOME)/.local/bin/kind
	
nginx: 
	docker run --rm -v ./:/usr/share/nginx/html:ro -d -p 8000:80 nginx:alpine

create-cluster:  ## Deploy kind cluster with local registry
	sh -c cluster/cluster-local-registry.sh
deploy-flux: ## Deploy-flux
	helm upgrade --install flux -n flux-system --create-namespace oci://registry-1.docker.io/bitnamicharts/flux \
	 --set imageReflectorController.enabled=false \
	 --set notificationController.enabled=false \
	 --set kustomizeController.enabled=false \
	 --set imageAutomationController.enabled=false \
	 --wait
destroy-cluster: ## Destroy kind cluter
	kind delete  cluster 
delete-http:
	kubectl delete hr -n flux-system http-cache 
	kubectl delete gitrepo -n flux-system ycdn
deploy: deploy-flux ## Deploy all apps
	helm upgrade --install cdn cdn/
	
temp: 
	helm template test http-cache/ -f http-cache/values-test.yaml --debug	


resize: ## Test image resize  performance
	wrk -c 64 -d 600s -s test/dynamic_urls.lua http://172.17.0.200

# https://cdn.dsmcdn.com/ty95/product/media/images/20210404/15/4da1b14b/13623803/1/1_org_zoom.jpg
# http://172.17.0.200/resize/300/400/aHR0cHM6Ly9jZG4uZHNtY2RuLmNvbS90eTk1L3Byb2R1Y3QvbWVkaWEvaW1hZ2VzLzIwMjEwNDA0LzE1LzRkYTFiMTRiLzEzNjIzODAzLzEvMV9vcmdfem9vbS5qcGc

