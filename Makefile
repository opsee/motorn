all: dev

build:
	docker build -t quay.io/opsee/motorn .

push: build
	docker push quay.io/opsee/motorn

dev: build
	docker run --rm -it \
	  --name motorn \
		-e JWE_KEY_FILE=vape.test.key \
	  -p 8080:80 \
	  quay.io/opsee/motorn
