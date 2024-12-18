#!/bin/bash
OUTPUT_PATH=${1:-storage}
EXCLUDE="test|mock|script|"

# FIXME: what does IFS do here?
IFS=$'\n'
CONTRACT_FILES=($(find ./src -type f))
unset IFS

echo "Outputting storage layouts to: $OUTPUT_PATH"
mkdir -p $OUTPUT_PATH

for file in "${CONTRACT_FILES[@]}";
do
    if [[ $file =~ .*($EXCLUDE).* ]]; then
        continue
    fi

    contract=$(basename "$file" .sol)
    echo "Generating storage layout for: $contract"
    forge inspect "$contract" storage --pretty > "$OUTPUT_PATH/$contract.md"
done
