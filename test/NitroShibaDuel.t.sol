// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {DSInvariantTest} from "solmate/test/utils/DSInvariantTest.sol";
import {console} from "forge-std/console.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC721} from "solmate/test/utils/mocks/MockERC721.sol";
import {ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";

import "../src/NitroShibaDuel.sol";

contract ERC721Recipient is ERC721TokenReceiver {
    address public operator;
    address public from;
    uint256 public id;
    bytes public data;

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _id,
        bytes calldata _data
    ) public virtual override returns (bytes4) {
        operator = _operator;
        from = _from;
        id = _id;
        data = _data;

        return ERC721TokenReceiver.onERC721Received.selector;
    }
}

contract RevertingERC721Recipient is ERC721TokenReceiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public virtual override returns (bytes4) {
        revert(string(abi.encodePacked(ERC721TokenReceiver.onERC721Received.selector)));
    }
}

contract WrongReturnDataERC721Recipient is ERC721TokenReceiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public virtual override returns (bytes4) {
        return 0xCAFEBEEF;
    }
}

contract NonERC721Recipient {}

contract NitroShibaDuelTest is DSTestPlus {

    /*//////////////////////////////////////////////////////////////
                SETUP
    //////////////////////////////////////////////////////////////*/

    MockERC20 token;
    MockERC721 nft;
    NitroShibaDuel game;

    // ether to wei unit conversion
    function etherToWei(uint256 _value) public pure returns (uint256) {
        return _value * (10 ** 18);
    }

    // Setup logic to run before each test
    function setUp() public {
        // Set up all contracts
        token = new MockERC20("Nitro Shiba", "NISHIB", 18);
        nft = new MockERC721("Nitro Shibas Family", "NSF");
        game = new NitroShibaDuel(
            address(token),
            address(nft),
            etherToWei(1),
            etherToWei(100),
            0,
            0
        );

        // Mint 0xABCD and 0xBEEF 100 tokens
        token.mint(address(0xABCD), etherToWei(100));
        token.mint(address(0xBEEF), etherToWei(100));

        // Mint 0xABCD and 0xBEEF 3 NFTs
        nft.mint(address(0xABCD), 1);
        nft.mint(address(0xBEEF), 2);
        nft.mint(address(0xABCD), 3);
        nft.mint(address(0xBEEF), 4);
        nft.mint(address(0xABCD), 5);
        nft.mint(address(0xBEEF), 6);

        // Give contract approvals
        // 0xABCD
        hevm.startPrank(address(0xABCD));
        token.approve(address(game), etherToWei(100));
        nft.setApprovalForAll(address(game), true);
        hevm.stopPrank();
        // 0xBEEF
        hevm.startPrank(address(0xBEEF));
        token.approve(address(game), etherToWei(100));
        nft.setApprovalForAll(address(game), true);
        hevm.stopPrank();
    }

    
    // Test initiateDuel()
    function testInitiateDuel() public {
        // Initiate duel as 0xABCD
        hevm.prank(address(0xABCD));
        uint256 duel = game.initiateDuel(1, etherToWei(10), NitroShibaDuel.Mode.SimpleBet);
        require(duel == 1, "duelID_INCORRECT");
    }

    // Test cancelDuel()
    function testCancelDuel() public {
        // Initiate duel as 0xABCD
        hevm.startPrank(address(0xABCD));
        game.initiateDuel(1, etherToWei(10), NitroShibaDuel.Mode.SimpleBet);
        game.cancelDuel(1);
        hevm.stopPrank();
    }
}