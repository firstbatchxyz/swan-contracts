#!/bin/bash

# Base directory for deployments
BASE_DIR="broadcast/Deploy.s.sol"
OUTPUT_DIR="deployment"

# Loop through each network directory under the base directory
for NETWORK_DIR in "$BASE_DIR"/*; do
  # Extract the network name from the directory path
  NETWORK=$(basename "$NETWORK_DIR")
  FILE_PATH="$NETWORK_DIR/run-latest.json"
  OUTPUT_FILE="$OUTPUT_DIR/$NETWORK.json"

  # Check if the run-latest.json file exists
  if [ ! -f "$FILE_PATH" ]; then
    echo "File not found: $FILE_PATH"
    continue
  fi

  # Create the output directory if it doesn't exist
  mkdir -p "$OUTPUT_DIR"

  # Initialize an empty JSON object
  echo "[" > "$OUTPUT_FILE"

# Read the file line by line
while IFS= read -r line; do
  # Look for CREATE transactions
  if [[ "$line" =~ \"transactionType\":\ \"CREATE\" ]]; then
    # Read next lines to extract contractName and contractAddress
    while IFS= read -r name_line; do
      if [[ "$name_line" =~ \"contractName\": ]]; then
        contract_name=$(echo "$name_line" | sed -n 's/.*"contractName": "\(.*\)",/\1/p')
      fi
      if [[ "$name_line" =~ \"contractAddress\": ]]; then
        contract_address=$(echo "$name_line" | sed -n 's/.*"contractAddress": "\(.*\)",/\1/p')
        # Write to the output JSON and break from the inner loop
        echo "  { \"contractName\": \"$contract_name\", \"contractAddress\": \"$contract_address\" }," >> "$OUTPUT_FILE"
        break
      fi
    done
  fi
done < "$FILE_PATH"

# Removing the trailing comma from the last line
sed -i '' -e '$ s/,$//' "$OUTPUT_FILE" 
echo "]" >> "$OUTPUT_FILE"

done