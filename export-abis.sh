#!/bin/bash

cp ./out/Swan.sol/Swan.json ./abis/Swan.json
node ./abis/parseAbi.js ./abis/Swan.json

cp ./out/SwanAgent.sol/SwanAgent.json ./abis/SwanAgent.json
node ./abis/parseAbi.js ./abis/SwanAgent.json

cp ./out/SwanArtifact.sol/SwanArtifact.json ./abis/SwanArtifact.json
node ./abis/parseAbi.js ./abis/SwanArtifact.json
