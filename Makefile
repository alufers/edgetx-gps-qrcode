
all: normal_version inverted_version
normal_version:
	mkdir -p dist
	(echo "-- Script for displaying GPS location of a model as a QR code. https://github.com/alufers/edgetx-gps-qrcode" && \
		luamin -f gps_qr.src.lua) > dist/GPSqr.lua

TEMP_FILE := $(shell mktemp)
inverted_version:
	mkdir -p dist
	cp gps_qr.src.lua $(TEMP_FILE)
	sed -i 's/local INVERTED = false/local INVERTED = true/' $(TEMP_FILE)
	(echo "-- Script for displaying GPS location of a model as a QR code (inverted display version). https://github.com/alufers/edgetx-gps-qrcode" && \
		luamin -f $(TEMP_FILE)) > dist/GPSqrI.lua
