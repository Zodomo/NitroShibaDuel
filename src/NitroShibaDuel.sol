// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";
import "openzeppelin-contracts/utils/Address.sol";
import "openzeppelin-contracts/utils/Counters.sol";

contract NitroShibaDuel {

    using Address for address;
    using Counters for Counters.Counter;

    /*//////////////////////////////////////////////////////////////
                STORAGE
    //////////////////////////////////////////////////////////////*/

    // Token and NFT contract addresses
    // Immutable to prevent any changes whatsoever
    address immutable nishibToken = 0x4DAD357726b41bb8932764340ee9108cC5AD33a0;
    address immutable nishibNFT = 0x74B8e48823658af4296814a8eC6baf271BcFa1e0;

    // Incremential duel count value is used as duel identifier
    Counters.Counter public duelCount;

    // Stores user $NISHIB balances for contract logic
    mapping(address => uint256) public nishibBalances;

    // Mode enum determines duel mode
    enum Mode {
        SimpleBet,
        DoubleOrNothing,
        PVP,
        PVPPlus,
        Jackpot
    }
    // Status enum determines duel status
    enum Status {
        Pending,
        Completed,
        Canceled
    }

    // Duel struct handles interaction and match data
    struct Duel {
        address[] addresses; // Player addresses, first is initiator
        uint256[] tokenIDs; // Player NFT tokenIDs, one per player, indexed by player address
        uint256[] outcomes; // Player VRF outcome values, highest always wins
        uint256 bet; // Static $NISHIB bet per player
        Mode mode; // Game mode
        Status status; // Game status
        address winner; // Winner address
        uint256 tokenPayout; // Total $NISHIB payout
        uint256 nftPayout; // NFT payout, if any
    }
    // bytes32 duel identifier to Duel struct
    mapping(uint256 => Duel) public duels;

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