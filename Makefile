##
# pacaur - An AUR helper that minimizes user interaction
##

VERSION = $(shell git describe --always | sed 's%-%.%g')

PREFIX = /usr/local

BINDIR = $(PREFIX)/bin
DATAROOTDIR = $(PREFIX)/share
DOCDIR = $(DATAROOTDIR)/doc/pacaur
MANPREFIX = $(DATAROOTDIR)/man
MSGFMT = $(shell command -v msgfmt 2>/dev/null)

TRANSLATIONS = \
	ca \
	da \
	de \
	es \
	fi \
	fr \
	hu \
	it \
	ja \
	nb \
	nl \
	pl \
	pt \
	ru \
	sk \
	sl \
	sr \
	sr@latin \
	tr \
	zh_CN

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
	@install -Dm644 ./config $(DESTDIR)$(DOCDIR)/config.example
	@install -Dm755 -t $(DESTDIR)$(BINDIR) ./pacaur
	@install -Dm644 -t $(DESTDIR)$(DATAROOTDIR)/pacaur ./libpacaur/*.sh
	@sed -i "s%declare -r pacaur_version=.*%declare -r pacaur_version=\'$(VERSION)\'%" $(DESTDIR)$(BINDIR)/pacaur
	@install -Dm644 ./completions/bash.completion $(DESTDIR)$(DATAROOTDIR)/bash-completion/completions/pacaur
	@install -Dm644 ./completions/zsh.completion $(DESTDIR)$(DATAROOTDIR)/zsh/site-functions/_pacaur
	@install -Dm644 ./LICENSE -t $(DESTDIR)$(DATAROOTDIR)/licenses/pacaur
	@install -Dm644 ./pacaur.8 -t $(DESTDIR)$(MANPREFIX)/man8
ifneq ($(MSGFMT),)
	for i in $(TRANSLATIONS); do \
		mkdir -p "$(DESTDIR)$(DATAROOTDIR)/locale/$$i/LC_MESSAGES/"; \
		$(MSGFMT) ./po/$$i.po -o "$(DESTDIR)$(DATAROOTDIR)/locale/$$i/LC_MESSAGES/pacaur.mo"; \
	done
endif

uninstall:
	@echo "Uninstalling..."
	@$(RM) $(DESTDIR)$(DOCDIR)/config.example
	@$(RM) $(DESTDIR)$(BINDIR)/pacaur
	@$(RM) $(DESTDIR)$(DATAROOTDIR)/bash-completion/completions/pacaur
	@$(RM) $(DESTDIR)$(DATAROOTDIR)/zsh/site-functions/_pacaur
	@$(RM) $(DESTDIR)$(DATAROOTDIR)/licenses/pacaur/LICENSE
	@$(RM) $(DESTDIR)$(MANPREFIX)/man8/pacaur.8
	@for i in $(TRANSLATIONS); do \
		$(RM) "$(DESTDIR)$(DATAROOTDIR)/locale/$$i/LC_MESSAGES/pacaur.mo"; \
	done

clean:
	@echo "Cleaning..."
	@$(RM) ./pacaur.8

.PHONY: doc install uninstall clean
