BASE_IMAGE ?= scratch
REPO ?= quay.io/yshnaidm/simple-device-plugin
TAG ?= latest
IMG ?= $(REPO):$(TAG)

CONTAINER_RUNTIME_COMMAND ?= docker

KUSTOMIZE_CONFIG_DEFAULT ?= config/default

NAMESPACE ?= simple-device-plugin
RESOURCE_NAME ?= example.com/simple-device
NUMBER_DEVICES ?= 2
PLUGIN_NAME ?= simple-device-plugin
DEVICE_ID_PREFIX ?= simple-device
ANNOTATION_PREFIX ?= ''
ENV_PREFIX ?= ''
DEVICE_FILE_PREFIX ?= ''

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

KUSTOMIZE ?= $(LOCALBIN)/kustomize
KUBECTL ?= $(LOCALBIN)/kubectl

KUBECTL_ARCH ?= arm64
ifeq ($(shell arch), x86_64)
	KUBECTL_ARCH = amd64
endif

# Use the latest release if no version is specified, see https://github.com/kubernetes-sigs/kustomize/releases
KUSTOMIZE_VERSION ?= ''
KUSTOMIZE_INSTALL_SCRIPT ?= "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"

.PHONY: kustomize
kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary.
$(KUSTOMIZE): $(LOCALBIN)
	test -s $(LOCALBIN)/kustomize || { curl -Ssf $(KUSTOMIZE_INSTALL_SCRIPT) | bash -s -- $(subst v,,$(KUSTOMIZE_VERSION)) $(LOCALBIN); }

# Use the latest release if no version is specified
KUBECTL_VERSION ?= $(shell curl --no-progress-meter -SsLf https://dl.k8s.io/release/stable.txt)

.PHONY: kubectl
kubectl: $(KUBECTL) ## Download kubectl locally if necessary
$(KUBECTL): $(LOCALBIN)
	test -s $(LOCALBIN)/kubectl || curl --no-progress-meter -SsLf https://dl.k8s.io/release/$(KUBECTL_VERSION)/bin/linux/$(KUBECTL_ARCH)/kubectl -o $(LOCALBIN)/kubectl && \
		chmod u+x $(LOCALBIN)/kubectl && echo "kubectl $(KUBECTL_VERSION) installed to $(LOCALBIN)/kubectl"

fmt:
	go fmt ./...

.PHONY: image
image:
	$(CONTAINER_RUNTIME_COMMAND) build \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
	-t $(IMG) .

.PHONY: image-push
image-push:
	$(CONTAINER_RUNTIME_COMMAND) push $(IMG)

deploy: kustomize kubectl
	cd config/device-plugin && $(KUSTOMIZE) edit set image device-plugin=$(IMG)
	cd config/default && $(KUSTOMIZE) edit set namespace $(NAMESPACE)
	sed -e 's#RESOURCE_NAME#$(RESOURCE_NAME)#g' \
		-e 's#NUMBER_DEVICES#$(NUMBER_DEVICES)#g' \
	       	-e 's#PLUGIN_NAME#$(PLUGIN_NAME)#g' \
		-e 's#DEVICE_ID_PREFIX#$(DEVICE_ID_PREFIX)#g' \
		-e 's#ANNOTATION_PREFIX#$(ANNOTATION_PREFIX)#g' \
		-e 's#ENV_PREFIX#$(ENV_PREFIX)#g' \
		-e 's#DEVICE_FILE_PREFIX#$(DEVICE_FILE_PREFIX)#g' \
		config/device-plugin/device_plugin_config_template.yaml > config/device-plugin/device_plugin_config.yaml
	#$(KUSTOMIZE) build config/default
	$(KUBECTL) apply -k config/default

undeploy: kubectl
	$(KUBECTL) delete -k config/default --ignore-not-found=false

