# Excalidraw QuickLook — build, sign and register the preview extensions.
#
# There is no Xcode project on purpose: the whole thing is four small Swift
# targets and two Info.plists, and swiftc assembles the bundle in one recipe.

APP_ID      := dev.alxhill.excalidraw-quicklook
APP         := build/ExcalidrawQuickLook.app
INSTALL_DIR ?= /Applications
INSTALLED   := $(INSTALL_DIR)/ExcalidrawQuickLook.app

SWIFTC      := xcrun swiftc
TARGET      := $(shell uname -m)-apple-macos13.0
SWIFT_FLAGS := -O -swift-version 5 -target $(TARGET)

KIT        := $(wildcard Sources/ExcalidrawKit/*.swift)
SOURCES    := $(KIT) $(wildcard Sources/*/*.swift)
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: all app cli install uninstall reinstall status test fonts clean

all: app cli

## Build the host app with both extensions inside it.
app: $(APP)

$(APP): $(SOURCES) $(wildcard Support/*) $(wildcard Resources/Fonts/*)
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources" "$(APP)/Contents/PlugIns"
	cp Support/App-Info.plist "$(APP)/Contents/Info.plist"
	printf 'APPL????' > "$(APP)/Contents/PkgInfo"
	$(SWIFTC) $(SWIFT_FLAGS) -module-name ExcalidrawQuickLook \
		-framework AppKit \
		-o "$(APP)/Contents/MacOS/ExcalidrawQuickLook" \
		Sources/Host/main.swift
	$(MAKE) appex KIND=Preview EXEC=ExcalidrawPreview FRAMEWORKS="-framework AppKit -framework Quartz"
	$(MAKE) appex KIND=Thumbnail EXEC=ExcalidrawThumbnail FRAMEWORKS="-framework AppKit -framework QuickLookThumbnailing"
	if [ -n "$$(ls Resources/Fonts/*.ttf Resources/Fonts/*.otf 2>/dev/null)" ]; then \
		mkdir -p "$(APP)/Contents/Resources/Fonts"; \
		cp Resources/Fonts/*.ttf Resources/Fonts/*.otf "$(APP)/Contents/Resources/Fonts/" 2>/dev/null || true; \
	fi
	codesign --force --sign - --timestamp=none "$(APP)"
	@echo "built $(APP)"

# App extensions are ordinary Mach-O executables whose entry point is
# NSExtensionMain, in a bundle whose Info.plist declares the extension point.
.PHONY: appex
appex:
	mkdir -p "$(APP)/Contents/PlugIns/$(EXEC).appex/Contents/MacOS"
	cp "Support/$(KIND)-Info.plist" "$(APP)/Contents/PlugIns/$(EXEC).appex/Contents/Info.plist"
	$(SWIFTC) $(SWIFT_FLAGS) -module-name $(EXEC) $(FRAMEWORKS) \
		-Xlinker -e -Xlinker _NSExtensionMain \
		-o "$(APP)/Contents/PlugIns/$(EXEC).appex/Contents/MacOS/$(EXEC)" \
		$(KIT) Sources/$(KIND)Extension/*.swift
	codesign --force --sign - --timestamp=none \
		--entitlements Support/Extension.entitlements \
		"$(APP)/Contents/PlugIns/$(EXEC).appex"

## Command-line renderer, for working on the renderer without Finder in the way.
cli: build/excalidraw-render

build/excalidraw-render: $(KIT) Sources/RenderCLI/main.swift
	mkdir -p build
	$(SWIFTC) $(SWIFT_FLAGS) -module-name ExcalidrawRender \
		-o $@ $(KIT) Sources/RenderCLI/main.swift

## Install into $(INSTALL_DIR) and register the extensions with the system.
install: app
	rm -rf "$(INSTALLED)"
	cp -R "$(APP)" "$(INSTALLED)"
	$(LSREGISTER) -f "$(INSTALLED)"
	pluginkit -a "$(INSTALLED)/Contents/PlugIns/ExcalidrawPreview.appex" || true
	pluginkit -a "$(INSTALLED)/Contents/PlugIns/ExcalidrawThumbnail.appex" || true
	pluginkit -e use -i $(APP_ID).preview || true
	pluginkit -e use -i $(APP_ID).thumbnail || true
	qlmanage -r >/dev/null 2>&1 || true
	qlmanage -r cache >/dev/null 2>&1 || true
	killall -q Finder || true
	@echo
	@echo "installed to $(INSTALLED)"
	@echo "select a .excalidraw file in Finder and press space."

uninstall:
	pluginkit -r "$(INSTALLED)/Contents/PlugIns/ExcalidrawPreview.appex" 2>/dev/null || true
	pluginkit -r "$(INSTALLED)/Contents/PlugIns/ExcalidrawThumbnail.appex" 2>/dev/null || true
	rm -rf "$(INSTALLED)"
	$(LSREGISTER) -kill -r -domain local -domain system -domain user >/dev/null 2>&1 || true
	qlmanage -r >/dev/null 2>&1 || true
	qlmanage -r cache >/dev/null 2>&1 || true
	killall -q Finder || true
	@echo "removed $(INSTALLED)"

reinstall: uninstall install

## Is the system actually using our extensions?
status:
	@echo "== installed"
	@test -d "$(INSTALLED)" && echo "$(INSTALLED)" || echo "not installed"
	@echo
	@echo "== registered extensions (a leading + means enabled)"
	@# -p com.apple.quicklook.thumbnail lists nothing even when the thumbnail
	@# extension is live, so ask for everything and filter by bundle id.
	@pluginkit -m -v -A 2>/dev/null | grep -i excalidraw || echo "none registered"

	@echo
	@echo "== .excalidraw content type"
	@mdls -name kMDItemContentType $(or $(FILE),$(firstword $(wildcard Tests/Fixtures/*.excalidraw))) 2>/dev/null || true

## Render every fixture (plus any FILES=... you pass) to build/renders.
test: cli
	@mkdir -p build/renders
	@for f in $(wildcard Tests/Fixtures/*.excalidraw) $(FILES); do \
		out="build/renders/$$(basename "$$f" .excalidraw).png"; \
		./build/excalidraw-render "$$f" "$$out" --size 1200 --scale 1 || exit 1; \
	done
	@echo "renders in build/renders"

## Optional: convert Excalidraw's own woff2 fonts to ttf so text matches the
## editor exactly. Needs network and uv; output is gitignored.
fonts:
	mkdir -p Resources/Fonts
	uv run --quiet --with fonttools --with brotli python scripts/fetch-fonts.py
	@echo "run 'make install' to pick the fonts up"

clean:
	rm -rf build
