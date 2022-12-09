// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";
import "openzeppelin-contracts/utils/Address.sol";

contract NitroShibaDuel {

    using Address for address;

    /*//////////////////////////////////////////////////////////////
                STORAGE
    //////////////////////////////////////////////////////////////*/

    // Token and NFT contract addresses
    // Immutable to prevent any changes whatsoever
    address immutable nishibToken = 0x4DAD357726b41bb8932764340ee9108cC5AD33a0;
    address immutable nishibNFT = 0x74B8e48823658af4296814a8eC6baf271BcFa1e0;

    // Stores user $NISHIB balances for contract logic
    mapping(address => uint256) public nishibBalances;

    // Mode enum determines duel mode
    enum Mode {
        SimpleBet,
        DoubleOrNothing,
        PVP,
        PVPPlus
    }
    // Status enum determines duel status
    enum Status {
        Pending,
        Completed,
        Canceled
    }

    // Duel struct handles interaction and match data
    struct Duel {
        address initiator; // Address of whoever initiates Duel
        uint256 initiatorNFT; // tokenID of the NFT initiator is dueling with
        address challenger; // Address of whoever challenges the initiator
        uint256 challengerNFT; // Challenger's dueling NFT tokenID
        uint256 bet; // $NISHIB bet
        Mode mode; // Game mode
        Status status; // Game status
        uint256 outcome; // VRF value determining winner <0.5 for initiator, >0.5 for challenger, rerolled if tie
    }
    // bytes32 duel identifier to Duel struct
    mapping(bytes32 => Duel) public duels;

    /*//////////////////////////////////////////////////////////////
                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {

    }

    /*//////////////////////////////////////////////////////////////
                IERC721Receiver
    //////////////////////////////////////////////////////////////*/

    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private returns (bool) {
        if (to.isContract()) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC721::_checkOnERC721Received::INVALID_RECIPIENT");
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    /*//////////////////////////////////////////////////////////////
                DUEL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    
}