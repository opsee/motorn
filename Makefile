REV ?= latest

all: dev

build:
	docker build -t quay.io/opsee/motorn:$(REV) .

push: build
	docker push quay.io/opsee/motorn:$(REV)

dev: build
	docker run --rm -it \
	  --name motorn \
		-e JWE_KEY_FILE=vape.test.key \
		-e UPSTREAMS=https://bartnet.in.opsee.com,https://beavis.in.opsee.com,https://keelhaul.in.opsee.com \
		-e STREAMING_UPSTREAMS=https://keelhaul.in.opsee.com \
	  -p 8083:8083 \
	  quay.io/opsee/motorn
