#!/bin/bash
OUTPUT_PATH=${1:-storage}
EXCLUDE="test|mock|script"

IFS=$'\n'
CONTRACT_FILES=($(find ./src -type f))
unset IFS

echo "Generating layouts in $OUTPUT_PATH"
mkdir -p $OUTPUT_PATH

for file in "${CONTRACT_FILES[@]}";
do
    if [[ $file =~ .*($EXCLUDE).* ]]; then
        continue
    fi

    contract=$(basename "$file" .sol)
    echo "Generating storage layout of $contract"
    forge inspect "$contract" storage --pretty > "$OUTPUT_PATH/$contract.md"
done