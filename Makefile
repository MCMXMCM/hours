DERIVED_DATA := $(CURDIR)/.build/DerivedData

.PHONY: export-gpl-source check-gpl-source build

# Writes the editable GABC of every GPL-covered chant in the bundled
# databases to Content/. check-gpl-source verifies the committed export.
export-gpl-source:
	node Tools/ContentSource/export-gpl-source.mjs

check-gpl-source:
	node Tools/ContentSource/export-gpl-source.mjs --check

build:
	xcodebuild -quiet -project Hours.xcodeproj -scheme Hours \
		-configuration Debug -destination 'generic/platform=iOS Simulator' \
		-derivedDataPath '$(DERIVED_DATA)' CODE_SIGNING_ALLOWED=NO build
