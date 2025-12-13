#!/bin/bash

# ----------------------------------------------------------------------
# VORBEREITUNG UND PRÜFUNG DER ARGUMENTE
# ----------------------------------------------------------------------

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
  echo "Fehler: Drei Argumente sind erforderlich." >&2
  echo "Verwendung: $0 <pfad/zur/logdatei> <pfad/zum/modrinth.json> <pfad/zum/overrides-basisordner>" >&2
  exit 1
fi

LOG_FILE="$1"
JSON_FILE="$2"
# Der Pfad zum Mods-Ordner im Overrides-Verzeichnis
OVERRIDES_PATH="$3/mods" 

# Temporäre Dateien für die bereinigten Mod-Listen erstellen
# LOG_JARS_FILE = Set A (Mods im Log)
LOG_JARS_FILE=$(mktemp)
# MODRINTH_JARS_FILE = Set B (Erwartete Mods: Modrinth + Overrides)
MODRINTH_JARS_FILE=$(mktemp) 

# Cleanup-Funktion, um temporäre Dateien am Ende zu löschen
trap "rm -f $LOG_JARS_FILE $MODRINTH_JARS_FILE" EXIT

# ----------------------------------------------------------------------
# 1. EXTRAKTION DER MODS AUS DEM LOG (SET A)
# ----------------------------------------------------------------------

awk -F'|' '/\.jar[[:space:]]+\|/ {
  # Whitespace entfernen
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); 
  # Nur nicht-leere Zeilen speichern
  if ($1 != "") print $1
}' "$LOG_FILE" | sort -u > "$LOG_JARS_FILE"

# ----------------------------------------------------------------------
# 2. KOMBINIERTE EXTRAKTION DER ERWARTETEN MODS (SET B)
# ----------------------------------------------------------------------

# a) Jars aus Modrinth-Index (.path) extrahieren
MODRINTH_JARS=$(
  jq -r '.files[] | 
    select(.path | endswith(".jar")) | 
    .path' "$JSON_FILE" \
    | sed -E 's|^.*/||' # Nur Dateiname extrahieren
)

# b) Jars aus dem Overrides-Ordner finden (rekursiv)
OVERRIDES_JARS=$(
  # find sucht alle .jar-Dateien im mods-Ordner
  # 2>/dev/null unterdrückt Fehlermeldungen, falls der Ordner nicht existiert
  find "$OVERRIDES_PATH" -type f -name "*.jar" 2>/dev/null \
    | sed -E 's|^.*/||' # Nur Dateiname extrahieren
)

# c) Beide Listen kombinieren, leere Zeilen filtern, sortieren und Duplikate entfernen (Union)
(echo "$MODRINTH_JARS"; echo "$OVERRIDES_JARS") | grep -v '^$' | sort -u > "$MODRINTH_JARS_FILE"


# ----------------------------------------------------------------------
# 3. VERGLEICH (COMM) UND JSON-AUSGABE (JQ)
# ----------------------------------------------------------------------

# Hilfsfunktion zum Konvertieren von Text in ein JSON-Array
to_json_array() {
  jq -Rs 'split("\n") | map(select(length > 0))'
}

# ADDITIONAL: Jars im Log (A), aber NICHT in Modrinth/Overrides (B) -> comm -23
ADDITIONAL_JSON=$(comm -23 "$LOG_JARS_FILE" "$MODRINTH_JARS_FILE" | to_json_array)

# MISSING: Jars in Modrinth/Overrides (B), aber NICHT im Log (A) -> comm -13
MISSING_JSON=$(comm -13 "$LOG_JARS_FILE" "$MODRINTH_JARS_FILE" | to_json_array)

# Endgültige JSON-Struktur erstellen und formatiert ausgeben
printf '{"additional_jars": %s, "missing_jars": %s}\n' "$ADDITIONAL_JSON" "$MISSING_JSON" | jq .