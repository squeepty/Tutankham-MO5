#!/usr/bin/env sh
set -eu

# Reproducible build pipeline:
#   1. validate the readable room source and flattened metadata tables;
#   2. pack the 21 immutable maps into generated assembly;
#   3. assemble raw/debug and DECB LOADM variants from the same source;
#   4. wrap LOADM in a K7 cassette image;
#   5. enforce the RAM/stack guard and emit emulator loading notes.
#
# All generated files stay under build/. The script is intentionally POSIX sh
# so it does not depend on a particular interactive shell.
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC_DIR="$PROJECT_DIR/src"
BUILD_DIR="$PROJECT_DIR/build"
MAIN="$SRC_DIR/main.asm"

BIN_OUT="$BUILD_DIR/tutankham-mo5.bin"
LOADM_OUT="$BUILD_DIR/tutankham-mo5.loadm"
K7_OUT="$BUILD_DIR/tutankham-mo5.k7"
LIST_OUT="$BUILD_DIR/tutankham-mo5.lst"
MAP_OUT="$BUILD_DIR/tutankham-mo5.map"
PACKED_MAPS_OUT="$BUILD_DIR/maps-packed.asm"
LOAD_NOTES_OUT="$BUILD_DIR/DCMOTO_LOAD.txt"
AUTOTYPE_OUT="$BUILD_DIR/DCMOTO_AUTOTYPE.txt"

if ! command -v lwasm >/dev/null 2>&1; then
    echo "error: lwasm not found. Install LWTOOLS first." >&2
    exit 1
fi

if ! command -v node >/dev/null 2>&1; then
    echo "error: node not found. Install Node.js for K7 generation." >&2
    exit 1
fi

mkdir -p "$BUILD_DIR"

# Content validation runs before generation so an invalid map cannot be hidden
# inside an otherwise valid packed include.
node "$PROJECT_DIR/tools/validate-content.mjs" "$SRC_DIR/game/data.asm"
node "$PROJECT_DIR/tools/pack-maps.mjs" \
    "$SRC_DIR/game/data.asm" \
    "$PACKED_MAPS_OUT"

# Raw output supplies debugger symbols/listing and is the size-guard reference.
lwasm \
    --6809 \
    --format=raw \
    --includedir="$SRC_DIR" \
    --includedir="$BUILD_DIR" \
    --output="$BIN_OUT" \
    --list="$LIST_OUT" \
    --symbols \
    --map="$MAP_OUT" \
    "$MAIN"

# DECB output carries the load/execute metadata consumed by LOADM and make-k7.
lwasm \
    --6809 \
    --format=decb \
    --includedir="$SRC_DIR" \
    --includedir="$BUILD_DIR" \
    --output="$LOADM_OUT" \
    "$MAIN"

node "$PROJECT_DIR/tools/make-k7.mjs" "$LOADM_OUT" "$K7_OUT" TUTANKHM

# Derive the occupied RAM range from the actual raw size and the assembly
# constant rather than duplicating PROGRAM_ORIGIN in this script.
BIN_SIZE=$(wc -c < "$BIN_OUT" | tr -d ' ')
LOAD_START_HEX=$(awk '
    $1 == "PROGRAM_ORIGIN" && $2 == "equ" {
        gsub(/^\$/, "", $3)
        print $3
        exit
    }
' "$SRC_DIR/constants.asm")
LOAD_END_DEC=$((0x$LOAD_START_HEX + BIN_SIZE - 1))
LOAD_END_HEX=$(printf "%04X" "$LOAD_END_DEC")

if [ "$LOAD_END_DEC" -ge $((0x9800)) ]; then
    echo "error: binary crosses the initial stack guard at $9800." >&2
    exit 1
fi

{
    printf "Tutankham MO5 nine-stage game\n"
    printf "\n"
    printf "Raw binary: %s\n" "$BIN_OUT"
    printf "Start address: $%s\n" "$LOAD_START_HEX"
    printf "End address:   $%s\n" "$LOAD_END_HEX"
    printf "Exec address:  $%s\n" "$LOAD_START_HEX"
    printf "\n"
    printf "Cassette: %s\n" "$K7_OUT"
    printf "Attach it in DCMOTO, open Fichier > Simuler le clavier, and\n"
    printf "paste LOADM\"\",,R or select %s.\n" "$AUTOTYPE_OUT"
} > "$LOAD_NOTES_OUT"

printf "LOADM\"\",,R\n" > "$AUTOTYPE_OUT"

echo "Tutankham MO5 nine-stage game assembled"
echo "  size:       $BIN_SIZE bytes"
echo "  range:      \$$LOAD_START_HEX-\$$LOAD_END_HEX"
echo "  binary:     $BIN_OUT"
echo "  cassette:   $K7_OUT"
echo "  load notes: $LOAD_NOTES_OUT"
echo "  autotype:   $AUTOTYPE_OUT"
