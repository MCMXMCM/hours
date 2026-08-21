DERIVED_DATA := $(CURDIR)/.build/DerivedData
SIMULATOR ?= platform=iOS Simulator,name=iPhone 17 Pro,OS=latest

.PHONY: compiler-test export-gpl-source generate-glyphs native-notation-validate high-risk-observance-audit fixture pilot-fixture development-corpus scored-development-corpus install-scored-development-corpus perennial-ordo perennial-source-cache perennial-preview install-perennial-preview perennial-release install-perennial-release build build-for-testing test

EXSURGE_GLYPHS ?= ../exsurge/src/Exsurge.Glyphs.js
DIVINUM_OFFICIUM_ROOT ?= ../divinum-officium
CHANT_TOOLS_ROOT ?= ../jgabc
CORPUS_YEAR ?= 2026
PERENNIAL_FROM_YEAR ?= 1962
PERENNIAL_TO_YEAR ?= 2100
RELEASE_CENTER_YEAR ?= 2026
RELEASE_FROM_YEAR ?= $(shell expr $(RELEASE_CENTER_YEAR) - 1)
RELEASE_TO_YEAR ?= $(shell expr $(RELEASE_CENTER_YEAR) + 10)
PERENNIAL_ORDO ?= Tools/ContentCompiler/Output/ordo-1962-2100.json
PERENNIAL_SOURCE_CACHE ?= Tools/ContentCompiler/Output/perennial-source-cache.sqlite
PERENNIAL_CATALOG ?= Tools/ContentCompiler/Output/2026-final-v2.sqlite
PERENNIAL_PREVIEW ?= Tools/ContentCompiler/Output/office-$(RELEASE_FROM_YEAR)-$(RELEASE_TO_YEAR)-preview.sqlite
PERENNIAL_RELEASE ?= Tools/ContentCompiler/Output/office-$(RELEASE_FROM_YEAR)-$(RELEASE_TO_YEAR)-release.sqlite

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

# Keep the complete 1962–2100 civil-date schedule as the local parity oracle.
# The installed database is a deterministic rolling 12-year window spanning
# the previous year through ten years after RELEASE_CENTER_YEAR; changing the
# release center never changes the
# reviewed long-range fixture.
perennial-ordo: compiler-test
	node Tools/ContentCompiler/Sources/cli.ts export-perennial-ordo \
		--source-root '$(DIVINUM_OFFICIUM_ROOT)' \
		--output '$(PERENNIAL_ORDO)' \
		--from '$(PERENNIAL_FROM_YEAR)' \
		--to '$(PERENNIAL_TO_YEAR)'

perennial-source-cache: perennial-ordo
	node Tools/ContentCompiler/Sources/cli.ts cache-perennial-recipes \
		--ordo '$(PERENNIAL_ORDO)' \
		--source-root '$(DIVINUM_OFFICIUM_ROOT)' \
		--cache '$(PERENNIAL_SOURCE_CACHE)' \
		--window-from '$(RELEASE_FROM_YEAR)-01-01' \
		--window-to '$(RELEASE_TO_YEAR)-12-31'

perennial-preview: perennial-source-cache
	node Tools/ContentCompiler/Sources/cli.ts compile-perennial-preview \
		--ordo '$(PERENNIAL_ORDO)' \
		--cache '$(PERENNIAL_SOURCE_CACHE)' \
		--catalog '$(PERENNIAL_CATALOG)' \
		--divinum-input 'Tools/ContentCompiler/Snapshots/$(CORPUS_YEAR)' \
		--window-from '$(RELEASE_FROM_YEAR)-01-01' \
		--window-to '$(RELEASE_TO_YEAR)-12-31' \
		--output '$(PERENNIAL_PREVIEW)'

install-perennial-preview: perennial-preview
	cp '$(PERENNIAL_PREVIEW)' HoursApp/Resources/base-office.sqlite
	$(MAKE) native-notation-validate

perennial-release: perennial-source-cache
	node Tools/ContentCompiler/Sources/cli.ts compile-perennial-release \
		--ordo '$(PERENNIAL_ORDO)' \
		--cache '$(PERENNIAL_SOURCE_CACHE)' \
		--catalog '$(PERENNIAL_CATALOG)' \
		--divinum-input 'Tools/ContentCompiler/Snapshots/$(CORPUS_YEAR)' \
		--window-from '$(RELEASE_FROM_YEAR)-01-01' \
		--window-to '$(RELEASE_TO_YEAR)-12-31' \
		--output '$(PERENNIAL_RELEASE)'

install-perennial-release: perennial-release
	cp '$(PERENNIAL_RELEASE)' HoursApp/Resources/base-office.sqlite
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
