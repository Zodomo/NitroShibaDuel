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

    address immutable nishibNFT = 0x74B8e48823658af4296814a8eC6baf271BcFa1e0;

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
}