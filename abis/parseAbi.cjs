const fs = require("fs");

if (process.argv.length < 3) {
  console.error("Please provide a filename as a parameter.");
  process.exit(1);
}

const filename = process.argv[2];

const data = fs.readFileSync(filename, "utf8");
try {
  const jsonData = JSON.parse(data);
  const abi = jsonData.abi;
  if (!abi) {
    console.error("No `abi` field found in the JSON data.");
    process.exit(1);
  }

  fs.writeFileSync(filename, JSON.stringify(abi, null, 2));
  console.log("ABI extracted and written to", filename);
} catch (parseErr) {
  console.error(`Error parsing JSON: ${parseErr}`);
  process.exit(1);
}
