EXEC_NAME := simple-device-plugin
GO_FILES ?= $$(find . -name '*.go' -not -path './vendor/*')
IMG ?= $(REPO):$(TAG)

build:
	go build -o $(EXEC_NAME) ./main.go

fmt:
	gofmt -w -s $(GO_FILES)

image:
	docker build -t $(IMG) .

clean:
	rm -f $(EXEC_NAME)

.PHONY: build image clean
