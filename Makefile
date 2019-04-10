##
# pacaur - An AUR helper that minimizes user interaction
##

VERSION = $(shell git describe --always | sed 's%-%.%g')

PREFIX ?= /usr/local
MANPREFIX ?= $(PREFIX)/share/man

# default target
all: doc

# documentation
doc:
	@echo "Generating documentation..."
	@pod2man --utf8 --section=8 --center="Pacaur Manual" --name="PACAUR" \
	--release="pacaur $(VERSION)" ./README.pod ./pacaur.8

# aux
install: doc
	@echo "Installing..."
	@install -Dm644 ./config $(DESTDIR)/etc/xdg/pacaur/config
	@install -Dm755 ./pacaur -t $(DESTDIR)$(PREFIX)/bin
	@install -Dm644 ./bash.completion $(DESTDIR)$(PREFIX)/share/bash-completion/completions/pacaur
	@install -Dm644 ./zsh.completion $(DESTDIR)$(PREFIX)/share/zsh/site-functions/_pacaur
	@install -Dm644 ./pacaur.8 -t $(DESTDIR)$(MANPREFIX)/man8
	@install -Dm644 ./LICENSE -t $(DESTDIR)$(PREFIX)/share/licenses/pacaur
	@for i in ca da de es fi fr hu it ja nb nl pl pt ru sk sl sr sr@latin tr zh_CN; do \
		mkdir -p "$(DESTDIR)$(PREFIX)/share/locale/$$i/LC_MESSAGES/"; \
		msgfmt ./po/$$i.po -o "$(DESTDIR)$(PREFIX)/share/locale/$$i/LC_MESSAGES/pacaur.mo"; \
	done

uninstall:
	@echo "Uninstalling..."
	@$(RM) $(DESTDIR)/etc/xdg/pacaur/config
	@$(RM) $(DESTDIR)$(PREFIX)/bin/pacaur
	@$(RM) $(DESTDIR)$(PREFIX)/share/bash-completion/completions/pacaur
	@$(RM) $(DESTDIR)$(PREFIX)/share/zsh/site-functions/_pacaur
	@$(RM) $(DESTDIR)$(MANPREFIX)/man8/pacaur.8
	@$(RM) $(DESTDIR)$(PREFIX)/share/licenses/pacaur/LICENSE
	@for i in ca da de es fi fr hu it ja nb nl pl pt ru sk sl sr sr@latin tr zh_CN; do \
		$(RM) "$(DESTDIR)$(PREFIX)/share/locale/$$i/LC_MESSAGES/pacaur.mo"; \
	done

clean:
	@echo "Cleaning..."
	@$(RM) ./pacaur.8

.PHONY: doc install uninstall clean
