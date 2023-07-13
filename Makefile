EXEC_NAME := simple-device-plugin
GO_FILES ?= $$(find . -name '*.go' -not -path './vendor/*')
IMG ?= $(REPO):$(TAG)
KUSTOMIZE_CONFIG_DEFAULT ?= config/default
KUSTOMIZE = $(shell pwd)/bin/kustomize

NAMESPACE := $(or ${NAMESPACE},simple-device-plugin)
RESOURCE_NAME := $(or ${RESOURCE_NAME},example.com/simple-device)
NUMBER_DEVICES := $(or ${NUMBER_DEVICES},2)
PLUGIN_NAME := $(or ${PLUGIN_NAME},simple-device-plugin)
DEVICE_ID_PREFIX := $(or ${DEVICE_ID_PREFIX},simple-device)
ANNOTATION_PREFIX := $(or ${ANNOTATION_PREFIX},)
ENV_PREFIX := $(or ${ENV_PREFIX},)
DEVICE_FILE_PREFIX := $(or ${DEVICE_FILE_PREFIX},)

.PHONY: kustomize
kustomize: ## Download kustomize locally if necessary.
	@if [ ! -f ${KUSTOMIZE} ]; then \
		BINDIR=$(shell pwd)/bin ./hack/download-kustomize; \
	fi

build:
	go build -o $(EXEC_NAME) ./main.go ./config.go

fmt:
	go fmt ./...

image: build
	docker build -t $(IMG) .

deploy: kustomize
	cd config/device-plugin && kustomize edit set image device-plugin=$(IMG)
	cd config/default && kustomize edit set namespace $(NAMESPACE)
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

.PHONY: build image clean
