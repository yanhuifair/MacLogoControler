APP := build/MacLogoControl.app
INSTALL_DIR ?= /Applications

# Quits a running Mac Logo Control (yours only) and waits up to 2 s for it to exit. It quits cleanly,
# returning the logo to normal first, and `open` would otherwise find the old one still running. One
# that's still running after that is blocked (e.g. showing the password dialog) and would only quit
# once that's answered, so it's killed, rather than letting the new build start beside it. A `LogoLight`
# is the app under its old name: it writes to the same logo, so it must go too.
QUIT_APP = pkill -x -U "$$(id -u)" "MacLogoControl|LogoLight"; for i in $$(seq 20); do pgrep -x -U "$$(id -u)" "MacLogoControl|LogoLight" > /dev/null || break; sleep 0.1; done; if pgrep -x -U "$$(id -u)" "MacLogoControl|LogoLight" > /dev/null; then echo 'Mac Logo Control did not quit (waiting for a password?); killing it'; pkill -KILL -x -U "$$(id -u)" "MacLogoControl|LogoLight"; sleep 0.2; fi; true

.PHONY: build test app dist run install uninstall clean

## build: compile everything (debug)
build:
	swift build

## test: run the test suite
test:
	swift run MacLogoControlTests

## app: build build/MacLogoControl.app
app:
	scripts/build-app.sh

## dist: build, sign, notarize and zip into dist/ (needs SIGN_IDENTITY and NOTARY_PROFILE)
dist:
	@test -n "$(SIGN_IDENTITY)" || { echo "Set SIGN_IDENTITY to your Developer ID Application identity"; exit 1; }
	scripts/build-app.sh
	scripts/notarize.sh

## run: build and open the app
run: app
	$(QUIT_APP)
	open $(APP)

## install: copy the app to /Applications (override with INSTALL_DIR=...)
install: app
	$(QUIT_APP)
	rm -rf "$(INSTALL_DIR)/MacLogoControl.app" "$(INSTALL_DIR)/LogoLight.app"
	cp -R $(APP) "$(INSTALL_DIR)/"
	open "$(INSTALL_DIR)/MacLogoControl.app"

## uninstall: remove the app (uncheck "Disable Password" first to remove its sudoers rule)
uninstall:
	$(QUIT_APP)
	rm -rf "$(INSTALL_DIR)/MacLogoControl.app" "$(INSTALL_DIR)/LogoLight.app"

clean:
	rm -rf .build build
