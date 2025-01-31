// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Factory contract to deploy Artifact tokens.
/// @dev This saves from contract space for Swan.
contract SwanArtifactFactory {
    /// @notice Deploys a new Artifact token.
    function deploy(string memory _name, string memory _symbol, bytes memory _description, address _owner)
        external
        returns (SwanArtifact)
    {
        return new SwanArtifact(_name, _symbol, _description, _owner, msg.sender);
    }
}

/// @notice Artifact is an ERC721 token with a single token supply.
contract SwanArtifact is ERC721, Ownable {
    /// @notice Creation time of the token
    uint256 public createdAt;
    /// @notice Description of the token
    bytes public description;

    /// @notice Constructor sets properties of the token.
    constructor(string memory _name, string memory _symbol, bytes memory _description, address _owner)
        ERC721(_name, _symbol)
        Ownable(_owner)
    {
        description = _description;
        createdAt = block.timestamp;

        // owner is minted the token immediately
        ERC721._safeMint(_owner, 1);

        // Swan (operator) is approved to by the owner immediately.
        ERC721._setApprovalForAll(_owner, _operator, true);
    }
}
