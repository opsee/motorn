all: dev

build:
	docker build -t quay.io/opsee/motorn .

push: build
	docker push quay.io/opsee/motorn

dev: build
	docker run --rm -it \
	  --name motorn \
		-e JWE_KEY_FILE=vape.test.key \
		-e UPSTREAMS=https://api-beta.opsee.co,https://events.opsee.co \
	  -p 8083:8083 \
	  quay.io/opsee/motorn
