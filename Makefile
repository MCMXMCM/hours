DERIVED_DATA := $(CURDIR)/.build/DerivedData
SIMULATOR ?= platform=iOS Simulator,name=iPhone 17 Pro,OS=latest

.PHONY: export-gpl-source check-gpl-source generate-glyphs native-notation-validator native-notation-validate build build-for-testing test

EXSURGE_GLYPHS ?= ../exsurge/src/Exsurge.Glyphs.js
OFFICE_RESOURCES := HoursApp/Resources/SharedOffice

# Writes the editable GABC of every GPL-covered chant in the bundled
# databases to Content/. check-gpl-source verifies the committed export.
export-gpl-source:
	node Tools/ContentSource/export-gpl-source.mjs

check-gpl-source:
	node Tools/ContentSource/export-gpl-source.mjs --check

generate-glyphs:
	node Tools/GlyphGenerator/generate.mjs \
		'$(EXSURGE_GLYPHS)' \
		HoursCore/GeneratedGregorianGlyphCatalog.swift

native-notation-validator:
	xcodebuild -quiet -project Hours.xcodeproj -scheme NotationValidator \
		-destination 'platform=macOS,arch=$(shell uname -m)' \
		-configuration Debug -derivedDataPath '$(DERIVED_DATA)' \
		CODE_SIGNING_ALLOWED=NO build

# Parses and engraves every chant in both bundled editions.
native-notation-validate: native-notation-validator
	'$(DERIVED_DATA)/Build/Products/Debug/NotationValidator' \
		'$(OFFICE_RESOURCES)/base-office.sqlite'
	'$(DERIVED_DATA)/Build/Products/Debug/NotationValidator' \
		'$(OFFICE_RESOURCES)/roman-1954-office.sqlite'

build:
	xcodebuild -quiet -project Hours.xcodeproj -scheme Hours \
		-configuration Debug -destination 'generic/platform=iOS Simulator' \
		-derivedDataPath '$(DERIVED_DATA)' CODE_SIGNING_ALLOWED=NO build

build-for-testing:
	xcodebuild -quiet -project Hours.xcodeproj -scheme Hours \
		-configuration Debug -destination 'generic/platform=iOS Simulator' \
		-derivedDataPath '$(DERIVED_DATA)' CODE_SIGNING_ALLOWED=NO build-for-testing

test: check-gpl-source native-notation-validate
	xcodebuild -quiet -project Hours.xcodeproj -scheme Hours \
		-configuration Debug -destination '$(SIMULATOR)' \
		-derivedDataPath '$(DERIVED_DATA)' CODE_SIGNING_ALLOWED=NO test
