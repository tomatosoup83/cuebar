.PHONY: build app run test icon clean format

build:
	swift build

app:
	./Scripts/build-app.sh

icon:
	swift Scripts/make-icon.swift icns waveform Resources/AppIcon.icns
	swift Scripts/make-icon.swift preview build/icon-previews

run:
	./Scripts/run.sh

test:
	swift test

clean:
	swift package clean
	rm -rf build
