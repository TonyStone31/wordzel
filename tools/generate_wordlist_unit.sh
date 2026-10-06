#!/bin/bash
# Regenerates unitwordlist.pas from the system dictionary.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="$SCRIPT_DIR/../unitwordlist.pas"

if [ -f /usr/share/dict/words ]; then
    INPUT_FILE="/usr/share/dict/words"
elif [ -f /usr/share/dict/american-english ]; then
    INPUT_FILE="/usr/share/dict/american-english"
elif [ -f /usr/dict/words ]; then
    INPUT_FILE="/usr/dict/words"
else
    echo "Error: No dictionary file found!"
    exit 1
fi

echo "Using dictionary: $INPUT_FILE"
echo "Generating Pascal unit: $OUTPUT_FILE"

# Filter words: only lowercase ASCII a-z, no special chars, 3-9 letters only, uppercase output
WORDS=$(LC_ALL=C grep -E "^[a-z]+$" "$INPUT_FILE" | \
        awk 'length($0) >= 3 && length($0) <= 9' | \
        tr '[:lower:]' '[:upper:]' | \
        sort -u)

WORD_COUNT=$(echo "$WORDS" | wc -l)
echo "Total words (3-9 letters): $WORD_COUNT"

cat > "$OUTPUT_FILE" << 'EOF'
unit unitwordlist;

{$mode objfpc}{$H+}

interface

const
  WORD_LIST: array[0..WORD_COUNT_PLACEHOLDER] of string = (
EOF

FIRST=true
while IFS= read -r word; do
    if [ "$FIRST" = true ]; then
        echo "    '$word'" >> "$OUTPUT_FILE"
        FIRST=false
    else
        echo "   ,'$word'" >> "$OUTPUT_FILE"
    fi
done <<< "$WORDS"

cat >> "$OUTPUT_FILE" << 'EOF'
  );

implementation

end.
EOF

ACTUAL_COUNT=$((WORD_COUNT - 1))
sed -i "s/WORD_COUNT_PLACEHOLDER/$ACTUAL_COUNT/" "$OUTPUT_FILE"

echo ""
echo "Pascal unit generated successfully!"
echo "Word count: $WORD_COUNT"
echo "Array indices: 0..$ACTUAL_COUNT"
