EXEC_NAME := simple-device-plugin
BASE_IMAGE ?= scratch
GO_FILES ?= $$(find . -name '*.go' -not -path './vendor/*')
REPO ?= quay.io/yshnaidm/simple-device-plugin
TAG ?= latest
IMG ?= $(REPO):$(TAG)
KUSTOMIZE_CONFIG_DEFAULT ?= config/default
KUSTOMIZE = $(shell pwd)/bin/kustomize

NAMESPACE ?= simple-device-plugin
RESOURCE_NAME ?= example.com/simple-device
NUMBER_DEVICES ?= 2
PLUGIN_NAME ?= simple-device-plugin
DEVICE_ID_PREFIX ?= simple-device
ANNOTATION_PREFIX ?= ''
ENV_PREFIX ?= ''
DEVICE_FILE_PREFIX ?= ''

CONTAINER_RUNTIME_COMMAND ?= docker

.PHONY: kustomize
kustomize: ## Download kustomize locally if necessary.
	@if [ ! -f ${KUSTOMIZE} ]; then \
		BINDIR=$(shell pwd)/bin ./hack/download-kustomize; \
	fi

build:
	go build -o $(EXEC_NAME) ./main.go ./config.go

fmt:
	go fmt ./...

.PHONY: image
image: build
	$(CONTAINER_RUNTIME_COMMAND) build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(IMG) .

.PHONY: image-push
image-push:
	$(CONTAINER_RUNTIME_COMMAND) push $(IMG)

deploy: kustomize
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
	kubectl apply -k config/default

undeploy:
	kubectl delete -k config/default --ignore-not-found=false

clean:
	rm -f $(EXEC_NAME)

.PHONY: build image push clean
