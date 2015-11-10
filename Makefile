all: dev

build:
	docker build -t quay.io/opsee/motorn:latest .

push: build
	docker push quay.io/opsee/motorn:latest

dev: build
	docker run --rm -it \
	  --name motorn \
		-e JWE_KEY_FILE=vape.test.key \
		-e UPSTREAMS=https://bartnet.in.opsee.com,https://beavis.in.opsee.com \
		-e STREAMING_UPSTREAMS=https://bartnet.in.opsee.com \
	  -p 8083:8083 \
	  quay.io/opsee/motorn
