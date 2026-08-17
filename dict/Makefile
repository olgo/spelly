VERSION  ?= de-2026.1
ENCODING ?= ISO-8859-15

SRC      := sources
DIST     := dist

# Handarbeit, im Repo. Getrennt von sources/, weil dort die Rohdaten von
# igerman98 liegen, die aus Lizenzgründen draussen bleiben – die Entscheidungen
# darüber, was gilt, sind dagegen unser eigenes Werk und wären beim nächsten
# frischen Klon sonst weg.
CURATION := curation
EXCLUDE  := $(CURATION)/propernouns.txt
INCLUDE  := $(CURATION)/extra.txt

.PHONY: all install clean check

all: $(DIST)/$(VERSION).dawg

# --- Quellen -------------------------------------------------------------
# igerman98 liefert de_DE.dic und de_DE.aff. Die Dateien nicht einchecken,
# sondern über dieses Ziel beziehen und die Lizenz in docs/ vermerken.
$(SRC)/de_DE.dic:
	@echo "Fehlt: $(SRC)/de_DE.dic und de_DE.aff"
	@echo "Beziehen von der igerman98-Projektseite und hier ablegen."
	@exit 1

# --- Verarbeitung --------------------------------------------------------
$(SRC)/fullforms.txt: $(SRC)/de_DE.dic scripts/expand.py
	python3 scripts/expand.py $< $@ --encoding $(ENCODING)

# Die beiden Kuratierungslisten sind echte Abhängigkeiten: Wer ein Wort
# nachträgt, bekommt beim nächsten `make` eine neue Wortliste, ohne an das
# Ausdehnen der Vollformen zu rühren.
$(SRC)/filtered.txt: $(SRC)/fullforms.txt $(EXCLUDE) $(INCLUDE) scripts/filter.py
	python3 scripts/filter.py $< $@ --exclude $(EXCLUDE) --include $(INCLUDE)

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
