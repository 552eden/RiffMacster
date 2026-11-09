BIN      := build/riffmacster
SOURCES  := $(wildcard Sources/riffmacster/*.swift)
PREFIX   := /usr/local/libexec
LABEL    := com.riffmacster.helper
PLIST    := /Library/LaunchDaemons/$(LABEL).plist

.PHONY: all test run install uninstall status logs clean

all: $(BIN)

$(BIN): $(SOURCES)
	@mkdir -p build
	swiftc -O -o $@ $(SOURCES)

test: $(BIN)
	./$(BIN) --selftest

# Run once by hand, without launchd (Ctrl-C to stop). Needs root.
run: $(BIN)
	sudo ./$(BIN) --foreground

install: $(BIN)
	@test "$$(id -u)" = 0 || { echo "run: sudo make install"; exit 1; }
	install -d -o root -g wheel $(PREFIX)
	install -o root -g wheel -m 755 $(BIN) $(PREFIX)/riffmacster
	install -o root -g wheel -m 644 launchd/$(LABEL).plist $(PLIST)
	-launchctl bootout system/$(LABEL) 2>/dev/null
	launchctl bootstrap system $(PLIST)
	@echo "Installed. RiffMacster now starts whenever the RiffMaster connects."

uninstall:
	@test "$$(id -u)" = 0 || { echo "run: sudo make uninstall"; exit 1; }
	-launchctl bootout system/$(LABEL) 2>/dev/null
	rm -f $(PLIST) $(PREFIX)/riffmacster
	@echo "Uninstalled."

status:
	@launchctl print system/$(LABEL) 2>/dev/null | grep -E 'state|pid|last exit' || echo "not installed"
	@pgrep -lx riffmacster || echo "helper not running"

logs:
	log stream --style compact --predicate 'subsystem == "com.riffmacster"'

clean:
	rm -rf build
