#!/bin/bash
forge compile

cp ./out/Swan.sol/Swan.json ./abis/Swan.json
node ./abis/parseAbi.cjs ./abis/Swan.json

cp ./out/SwanAgent.sol/SwanAgent.json ./abis/SwanAgent.json
node ./abis/parseAbi.cjs ./abis/SwanAgent.json

cp ./out/SwanArtifact.sol/SwanArtifact.json ./abis/SwanArtifact.json
node ./abis/parseAbi.cjs ./abis/SwanArtifact.json
