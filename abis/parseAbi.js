const fs = require("fs");

if (process.argv.length < 3) {
  console.error("Please provide a filename as a parameter.");
  process.exit(1);
}

const filename = process.argv[2];

fs.readFile(filename, "utf8", (err, data) => {
  if (err) {
    console.error(`Error reading file: ${err}`);
    process.exit(1);
  }

  try {
    const jsonData = JSON.parse(data);
    const abi = jsonData.abi;

    if (!abi) {
      console.error("No `abi` field found in the JSON data.");
      process.exit(1);
    }

    fs.writeFile(filename, JSON.stringify(abi, null, 2), (err) => {
      if (err) {
        console.error(`Error writing file: ${err}`);
        process.exit(1);
      }

      console.log("ABI extracted and written to abi.json");
    });
  } catch (parseErr) {
    console.error(`Error parsing JSON: ${parseErr}`);
    process.exit(1);
  }
});
