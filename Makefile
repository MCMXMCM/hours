DERIVED_DATA := $(CURDIR)/.build/DerivedData
SIMULATOR ?= platform=iOS Simulator,name=iPhone 17 Pro,OS=latest

.PHONY: compiler-test export-gpl-source generate-glyphs native-notation-validate high-risk-observance-audit fixture pilot-fixture development-corpus scored-development-corpus install-scored-development-corpus build build-for-testing test

EXSURGE_GLYPHS ?= ../exsurge/src/Exsurge.Glyphs.js
DIVINUM_OFFICIUM_ROOT ?= ../divinum-officium
CHANT_TOOLS_ROOT ?= ../jgabc
CORPUS_YEAR ?= 2026

export-gpl-source:
	node Tools/ContentSource/export-nocturnale.mjs

generate-glyphs:
	node Tools/GlyphGenerator/generate.mjs \
		'$(EXSURGE_GLYPHS)' \
		HoursCore/GeneratedGregorianGlyphCatalog.swift

compiler-test:
	node --test Tools/ContentCompiler/Tests/*.test.ts

high-risk-observance-audit:
	node Tools/ContentCompiler/Sources/cli.ts audit-observances \
		--input 'Tools/ContentCompiler/Snapshots/$(CORPUS_YEAR)-scored-reference' \
		--expectations 'Tools/ContentCompiler/Fixtures/$(CORPUS_YEAR)-high-risk-observances.json' \
		--divinum-input 'Tools/ContentCompiler/Snapshots/$(CORPUS_YEAR)'

fixture: compiler-test native-notation-validate

pilot-fixture: compiler-test
	node Tools/ContentCompiler/Sources/cli.ts compile \
		--input Tools/ContentCompiler/Fixtures/evening-pilot.json \
		--output HoursApp/Resources/base-office.sqlite \
		--allow-incomplete
	$(MAKE) native-notation-validate

development-corpus: compiler-test
	node Tools/ContentCompiler/Sources/cli.ts snapshot \
		--source-root '$(DIVINUM_OFFICIUM_ROOT)' \
		--output 'Tools/ContentCompiler/Snapshots/$(CORPUS_YEAR)' \
		--from '$(CORPUS_YEAR)-01-01' \
		--to '$(CORPUS_YEAR)-12-31'
	node Tools/ContentCompiler/Sources/cli.ts compile-snapshots \
		--input 'Tools/ContentCompiler/Snapshots/$(CORPUS_YEAR)' \
		--output 'Tools/ContentCompiler/Output/$(CORPUS_YEAR)-text-only.sqlite' \
		--seed Tools/ContentCompiler/Fixtures/evening-pilot.json

scored-development-corpus: compiler-test
	node Tools/ContentCompiler/Sources/cli.ts snapshot-scored-reference \
		--chant-tools-root '$(CHANT_TOOLS_ROOT)' \
		--output 'Tools/ContentCompiler/Snapshots/$(CORPUS_YEAR)-scored-reference' \
		--from '$(CORPUS_YEAR)-01-01' \
		--to '$(CORPUS_YEAR)-12-31'
	node Tools/ContentCompiler/Sources/cli.ts compile-scored-snapshots \
		--input 'Tools/ContentCompiler/Snapshots/$(CORPUS_YEAR)' \
		--scored-input 'Tools/ContentCompiler/Snapshots/$(CORPUS_YEAR)-scored-reference' \
		--output 'Tools/ContentCompiler/Output/$(CORPUS_YEAR)-scored-reference.sqlite'

install-scored-development-corpus: compiler-test
	node Tools/ContentCompiler/Sources/cli.ts compile-scored-snapshots \
		--input 'Tools/ContentCompiler/Snapshots/$(CORPUS_YEAR)' \
		--scored-input 'Tools/ContentCompiler/Snapshots/$(CORPUS_YEAR)-scored-reference' \
		--output HoursApp/Resources/base-office.sqlite \
		--allow-incomplete \
		--allow-reference-bundle
	$(MAKE) native-notation-validate

native-notation-validate:
	xcodebuild -quiet -project Hours.xcodeproj -scheme NotationValidator \
		-configuration Debug -derivedDataPath '$(DERIVED_DATA)' \
		CODE_SIGNING_ALLOWED=NO build
	'$(DERIVED_DATA)/Build/Products/Debug/NotationValidator' \
		HoursApp/Resources/base-office.sqlite

build:
	xcodebuild -quiet -project Hours.xcodeproj -scheme Hours \
		-configuration Debug -destination 'generic/platform=iOS Simulator' \
		-derivedDataPath '$(DERIVED_DATA)' CODE_SIGNING_ALLOWED=NO build

build-for-testing:
	xcodebuild -quiet -project Hours.xcodeproj -scheme Hours \
		-configuration Debug -destination 'generic/platform=iOS Simulator' \
		-derivedDataPath '$(DERIVED_DATA)' CODE_SIGNING_ALLOWED=NO build-for-testing

test: compiler-test native-notation-validate
	xcodebuild -quiet -project Hours.xcodeproj -scheme Hours \
		-configuration Debug -destination '$(SIMULATOR)' \
		-derivedDataPath '$(DERIVED_DATA)' CODE_SIGNING_ALLOWED=NO test
