VERSION  ?= de-2026.1
ENCODING ?= ISO-8859-15

SRC      := sources
DIST     := dist
EXCLUDE  := $(SRC)/propernouns.txt

.PHONY: all install clean check

all: $(DIST)/$(VERSION).dawg

# --- Quellen -------------------------------------------------------------
# igerman98 liefert de_DE.dic und de_DE.aff. Die Dateien nicht einchecken,
# sondern über dieses Ziel beziehen und die Lizenz in docs/ vermerken.
$(SRC)/de_DE.dic:
	@echo "Fehlt: $(SRC)/de_DE.dic und de_DE.aff"
	@echo "Beziehen von der igerman98-Projektseite und hier ablegen."
	@exit 1

# Ausschlussliste aus einem Wiktionary-Dump: alle Einträge mit Wortart
# Vorname, Nachname, Toponym oder Eigenname. Optional – fehlt sie, laeuft
# der Filter durch und meldet das.
$(EXCLUDE):
	@echo "Hinweis: $(EXCLUDE) fehlt, Eigennamen werden nicht gefiltert."
	@touch $@

# --- Verarbeitung --------------------------------------------------------
$(SRC)/fullforms.txt: $(SRC)/de_DE.dic scripts/expand.py
	python3 scripts/expand.py $< $@ --encoding $(ENCODING)

$(SRC)/filtered.txt: $(SRC)/fullforms.txt $(EXCLUDE) scripts/filter.py
	python3 scripts/filter.py $< $@ --exclude $(EXCLUDE)

$(DIST)/$(VERSION).dawg: $(SRC)/filtered.txt scripts/build_dawg.py
	mkdir -p $(DIST)
	python3 scripts/build_dawg.py $< $@

# --- Abnahme und Auslieferung -------------------------------------------
check: $(DIST)/$(VERSION).dawg
	python3 scripts/verify.py $< --source $(SRC)/filtered.txt

install: check
	cp $(DIST)/$(VERSION).dawg ../app/assets/dict/$(VERSION).dawg
	@echo "Denk daran, dict_version in der Datenbank auf $(VERSION) zu setzen."

clean:
	rm -rf $(DIST) $(SRC)/fullforms.txt $(SRC)/filtered.txt
