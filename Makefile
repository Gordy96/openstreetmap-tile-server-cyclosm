.PHONY: build import run

THIS_DIR := $(dir $(abspath $(firstword $(MAKEFILE_LIST))))

build:
	docker volume create openstreetmap-data
	docker build -t tile-base -f Dockerfile.base .
	docker build -t tile-server -f Dockerfile .

import: build
	docker run --rm \
	-e THREADS=24 \
	-v ${THIS_DIR}sql:/sql \
	-v ${THIS_DIR}data.osm.pbf:/data.osm.pbf \
	-v ${THIS_DIR}data.poly:/data.poly \
	-v openstreetmap-cyclosm-data:/var/lib/postgresql/12/main \
	-v ${THIS_DIR}contours:/contours tile-server import

contours_dl: build
	docker run --rm \
	-e THREADS=24 \
	-v ${THIS_DIR}contours:/contours tile-server contours_dl

contours_import: build
	docker run --rm \
	-e THREADS=24 \
	-v openstreetmap-cyclosm-data:/var/lib/postgresql/12/main \
	-v ${THIS_DIR}contours:/contours tile-server contours_import

run: build
	docker run \
	-p 8080:80 \
	-e THREADS=24 \
	-v openstreetmap-cyclosm-data:/var/lib/postgresql/12/main \
	-d tile-server \
	run
