// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {DSInvariantTest} from "solmate/test/utils/DSInvariantTest.sol";

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
        uint256 duelID = game.initiateDuel(1, etherToWei(10), NitroShibaDuel.Mode.SimpleBet);

        // Standard duel data checks
        (
            uint256 bet, NitroShibaDuel.Mode mode, NitroShibaDuel.Status status,
            uint256 deadline, bytes32 vrfSalt, bytes32 vrfDONSalt,
            address winner, uint256 participantCount, uint256 tokenPayout, uint256 nftPayout
        ) = game.getDuelData(1);

        require(duelID == 1, "duelID_INCORRECT");
        require(bet == etherToWei(10), "bet_INCORRECT");
        require(mode == NitroShibaDuel.Mode.SimpleBet, "mode_INCORRECT");
        require(status == NitroShibaDuel.Status.Initialized, "status_INCORRECT");
        require(deadline > 0, "deadline_INCORRECT");
        require(vrfSalt == bytes32(0), "vrfSalt_INCORRECT");
        require(vrfDONSalt == bytes32(0), "vrfDONSalt_INCORRECT");
        require(winner == address(0), "winner_INCORRECT");
        require(participantCount == 1, "participantCount_INCORRECT");
        require(tokenPayout == etherToWei(10), "tokenPayout_INCORRECT");
        require(nftPayout == 0, "nftPayout_INCORRECT");

        // Participant data checks
        (address participant, uint256 tokenId) = game.getDuelParticipant(duelID, 0);

        require(participant == address(0xABCD), "address_ERROR");
        require(tokenId == 1, "tokenId_ERROR");

        // Contract state checks
        require(token.balanceOf(address(game)) == etherToWei(10), "balanceOf_INCORRECT");
        require(game.nishibBalances(address(0xABCD)) == etherToWei(10), "nishibBalances_INCORRECT");
    }

    // Test two concurrent calls to initiateDuel()
    function testInitiateTwoDuels() public {
        // Initiate duels as 0xABCD
        hevm.startPrank(address(0xABCD));
        game.initiateDuel(1, etherToWei(10), NitroShibaDuel.Mode.SimpleBet);
        uint256 duelID = game.initiateDuel(1, etherToWei(20), NitroShibaDuel.Mode.SimpleBet);
        hevm.stopPrank();

        // Standard duel data checks
        (
            uint256 bet, NitroShibaDuel.Mode mode, NitroShibaDuel.Status status,
            uint256 deadline, bytes32 vrfSalt, bytes32 vrfDONSalt,
            address winner, uint256 participantCount, uint256 tokenPayout, uint256 nftPayout
        ) = game.getDuelData(duelID);

        require(duelID == 2, "duelID_INCORRECT");
        require(bet == etherToWei(20), "bet_INCORRECT");
        require(mode == NitroShibaDuel.Mode.SimpleBet, "mode_INCORRECT");
        require(status == NitroShibaDuel.Status.Initialized, "status_INCORRECT");
        require(deadline > 0, "deadline_INCORRECT");
        require(vrfSalt == bytes32(0), "vrfSalt_INCORRECT");
        require(vrfDONSalt == bytes32(0), "vrfDONSalt_INCORRECT");
        require(winner == address(0), "winner_INCORRECT");
        require(participantCount == 1, "participantCount_INCORRECT");
        require(tokenPayout == etherToWei(20), "tokenPayout_INCORRECT");
        require(nftPayout == 0, "nftPayout_INCORRECT");

        // Participant data checks
        (address participant, uint256 tokenId) = game.getDuelParticipant(duelID, 0);

        require(participant == address(0xABCD), "address_ERROR");
        require(tokenId == 1, "tokenId_ERROR");

        // Contract state checks
        require(token.balanceOf(address(game)) == etherToWei(30), "balanceOf_INCORRECT");
        require(game.nishibBalances(address(0xABCD)) == etherToWei(30), "nishibBalances_INCORRECT");
    }

    // Test cancelDuel() immediately after initiation
    function testCancelInitiatedDuel() public {
        // Initiate duel as 0xABCD
        hevm.startPrank(address(0xABCD));
        uint256 duelID = game.initiateDuel(1, etherToWei(10), NitroShibaDuel.Mode.SimpleBet);
        game.cancelDuel(duelID);
        hevm.stopPrank();

        // Standard duel data checks
        (
            uint256 bet, NitroShibaDuel.Mode mode, NitroShibaDuel.Status status,
            uint256 deadline, bytes32 vrfSalt, bytes32 vrfDONSalt,
            address winner, uint256 participantCount, uint256 tokenPayout, uint256 nftPayout
        ) = game.getDuelData(duelID);

        require(duelID == 1, "duelID_INCORRECT");
        require(bet == etherToWei(10), "bet_INCORRECT");
        require(mode == NitroShibaDuel.Mode.SimpleBet, "mode_INCORRECT");
        require(status == NitroShibaDuel.Status.Canceled, "status_INCORRECT");
        require(deadline > 0, "deadline_INCORRECT");
        require(vrfSalt == bytes32(0), "vrfSalt_INCORRECT");
        require(vrfDONSalt == bytes32(0), "vrfDONSalt_INCORRECT");
        require(winner == address(0), "winner_INCORRECT");
        require(participantCount == 1, "participantCount_INCORRECT");
        require(tokenPayout == 0, "tokenPayout_INCORRECT");
        require(nftPayout == 0, "nftPayout_INCORRECT");

        // Participant data checks
        (address participant, uint256 tokenId) = game.getDuelParticipant(duelID, 0);

        require(participant == address(0xABCD), "address_ERROR");
        require(tokenId == 1, "tokenId_ERROR");

        // Contract state checks
        require(token.balanceOf(address(game)) == 0, "balanceOf_INCORRECT");
        require(token.balanceOf(address(0xABCD)) == etherToWei(100), "REFUND_ERROR");
        require(game.nishibBalances(address(0xABCD)) == 0, "nishibBalances_INCORRECT");
    }

    // Test joining a duel
    function testJoinInitiatedDuel() public {
        // Initiate duel as 0xABCD
        hevm.prank(address(0xABCD));
        uint256 duelID = game.initiateDuel(1, etherToWei(10), NitroShibaDuel.Mode.SimpleBet);

        // Join duel as 0xBEEF
        hevm.prank(address(0xBEEF));
        game.joinDuel(2, duelID);

        // Standard duel data checks
        (
            uint256 bet, NitroShibaDuel.Mode mode, NitroShibaDuel.Status status,
            uint256 deadline, bytes32 vrfSalt, bytes32 vrfDONSalt,
            address winner, uint256 participantCount, uint256 tokenPayout, uint256 nftPayout
        ) = game.getDuelData(duelID);

        require(status == NitroShibaDuel.Status.Initialized, "status_INCORRECT");
        require(participantCount == 2, "participantCount_INCORRECT");
        require(tokenPayout == etherToWei(20), "tokenPayout_INCORRECT");

        // Participant data checks
        (address participant, uint256 tokenId) = game.getDuelParticipant(duelID, 0);

        require(participant == address(0xABCD), "address_ERROR");
        require(tokenId == 1, "tokenId_ERROR");

        (participant, tokenId) = game.getDuelParticipant(duelID, 1);

        require(participant == address(0xBEEF), "address_ERROR");
        require(tokenId == 2, "tokenId_ERROR");

        // Contract state checks
        require(token.balanceOf(address(game)) == etherToWei(20), "balanceOf_INCORRECT");
        require(game.nishibBalances(address(0xABCD)) == etherToWei(10), "nishibBalances_INCORRECT");
        require(game.nishibBalances(address(0xBEEF)) == etherToWei(10), "nishibBalances_INCORRECT");
    }

    // Test executing a duel
    function testExecuteDuelAsInitiator() public {
        // Initiate duel as 0xABCD
        hevm.prank(address(0xABCD));
        uint256 duelID = game.initiateDuel(1, etherToWei(10), NitroShibaDuel.Mode.SimpleBet);

        // Join duel as 0xBEEF
        hevm.prank(address(0xBEEF));
        game.joinDuel(2, duelID);

        // Execute duel as 0xABCD
        hevm.prank(address(0xABCD));
        game.executeDuel(duelID);

        // Standard duel data checks
        (
            uint256 bet, NitroShibaDuel.Mode mode, NitroShibaDuel.Status status,
            uint256 deadline, bytes32 vrfSalt, bytes32 vrfDONSalt,
            address winner, uint256 participantCount, uint256 tokenPayout, uint256 nftPayout
        ) = game.getDuelData(duelID);

        require(duelID == 1, "duelID_INCORRECT");
        require(bet == etherToWei(10), "bet_INCORRECT");
        require(mode == NitroShibaDuel.Mode.SimpleBet, "mode_INCORRECT");
        require(status == NitroShibaDuel.Status.Completed, "status_INCORRECT");
        require(deadline > 0, "deadline_INCORRECT");
        require(vrfSalt != bytes32(0), "vrfSalt_INCORRECT");
        require(vrfDONSalt == bytes32(0), "vrfDONSalt_INCORRECT");
        require(winner == address(0xABCD) || winner == address(0xBEEF), "winner_INCORRECT");
        require(participantCount == 2, "participantCount_INCORRECT");
        require(tokenPayout == etherToWei(20), "tokenPayout_INCORRECT");
        require(nftPayout == 0, "nftPayout_INCORRECT");

        // Participant data checks
        (address participant, uint256 tokenId) = game.getDuelParticipant(duelID, 0);

        require(participant == address(0xABCD), "address_ERROR");
        require(tokenId == 1, "tokenId_ERROR");

        (participant, tokenId) = game.getDuelParticipant(duelID, 1);

        require(participant == address(0xBEEF), "address_ERROR");
        require(tokenId == 2, "tokenId_ERROR");

        // Contract state checks
        require(token.balanceOf(address(game)) == etherToWei(20), "balanceOf_INCORRECT");
        if (winner == address(0xABCD)) {
            require(game.nishibBalances(address(0xABCD)) == etherToWei(20), "nishibBalances_INCORRECT");
            require(game.nishibBalances(address(0xBEEF)) == 0, "nishibBalances_INCORRECT");
        } else {
            require(game.nishibBalances(address(0xBEEF)) == etherToWei(20), "nishibBalances_INCORRECT");
            require(game.nishibBalances(address(0xABCD)) == 0, "nishibBalances_INCORRECT");
        }
    }

    // Test executing a duel
    function testExecuteDuelAsParticipant() public {
        // Initiate duel as 0xABCD
        hevm.prank(address(0xABCD));
        uint256 duelID = game.initiateDuel(1, etherToWei(10), NitroShibaDuel.Mode.SimpleBet);

        // Join duel as 0xBEEF
        hevm.prank(address(0xBEEF));
        game.joinDuel(2, duelID);

        // Execute duel as 0xBEEF
        hevm.prank(address(0xBEEF));
        game.executeDuel(duelID);

        // Standard duel data checks
        (
            uint256 bet, NitroShibaDuel.Mode mode, NitroShibaDuel.Status status,
            uint256 deadline, bytes32 vrfSalt, bytes32 vrfDONSalt,
            address winner, uint256 participantCount, uint256 tokenPayout, uint256 nftPayout
        ) = game.getDuelData(duelID);

        require(duelID == 1, "duelID_INCORRECT");
        require(bet == etherToWei(10), "bet_INCORRECT");
        require(mode == NitroShibaDuel.Mode.SimpleBet, "mode_INCORRECT");
        require(status == NitroShibaDuel.Status.Completed, "status_INCORRECT");
        require(deadline > 0, "deadline_INCORRECT");
        require(vrfSalt != bytes32(0), "vrfSalt_INCORRECT");
        require(vrfDONSalt == bytes32(0), "vrfDONSalt_INCORRECT");
        require(winner == address(0xABCD) || winner == address(0xBEEF), "winner_INCORRECT");
        require(participantCount == 2, "participantCount_INCORRECT");
        require(tokenPayout == etherToWei(20), "tokenPayout_INCORRECT");
        require(nftPayout == 0, "nftPayout_INCORRECT");

        // Participant data checks
        (address participant, uint256 tokenId) = game.getDuelParticipant(duelID, 0);

        require(participant == address(0xABCD), "address_ERROR");
        require(tokenId == 1, "tokenId_ERROR");

        (participant, tokenId) = game.getDuelParticipant(duelID, 1);

        require(participant == address(0xBEEF), "address_ERROR");
        require(tokenId == 2, "tokenId_ERROR");

        // Contract state checks
        require(token.balanceOf(address(game)) == etherToWei(20), "balanceOf_INCORRECT");
        if (winner == address(0xABCD)) {
            require(game.nishibBalances(address(0xABCD)) == etherToWei(20), "nishibBalances_INCORRECT");
            require(game.nishibBalances(address(0xBEEF)) == 0, "nishibBalances_INCORRECT");
        } else {
            require(game.nishibBalances(address(0xBEEF)) == etherToWei(20), "nishibBalances_INCORRECT");
            require(game.nishibBalances(address(0xABCD)) == 0, "nishibBalances_INCORRECT");
        }
    }

    // Test if winner can withdraw duel winnings
    function testWithdrawDuel() public {
        // Initiate duel as 0xABCD
        hevm.prank(address(0xABCD));
        uint256 duelID = game.initiateDuel(1, etherToWei(10), NitroShibaDuel.Mode.SimpleBet);

        // Join duel as 0xBEEF
        hevm.prank(address(0xBEEF));
        game.joinDuel(2, duelID);

        // Execute duel as 0xABCD
        hevm.prank(address(0xABCD));
        game.executeDuel(duelID);

        // Have winner withdrfaw
        (,,,,,,address duelWinner,,,) = game.getDuelData(duelID);
        hevm.prank(duelWinner);
        game.withdrawDuel(duelID);

        // Standard duel data checks
        (
            uint256 bet, NitroShibaDuel.Mode mode, NitroShibaDuel.Status status,
            uint256 deadline, bytes32 vrfSalt, bytes32 vrfDONSalt,
            address winner, uint256 participantCount, uint256 tokenPayout, uint256 nftPayout
        ) = game.getDuelData(duelID);

        require(duelID == 1, "duelID_INCORRECT");
        require(bet == etherToWei(10), "bet_INCORRECT");
        require(mode == NitroShibaDuel.Mode.SimpleBet, "mode_INCORRECT");
        require(status == NitroShibaDuel.Status.PotPaid, "status_INCORRECT");
        require(deadline > 0, "deadline_INCORRECT");
        require(vrfSalt != bytes32(0), "vrfSalt_INCORRECT");
        require(vrfDONSalt == bytes32(0), "vrfDONSalt_INCORRECT");
        require(winner == address(0xABCD) || winner == address(0xBEEF), "winner_INCORRECT");
        require(participantCount == 2, "participantCount_INCORRECT");
        require(tokenPayout == etherToWei(20), "tokenPayout_INCORRECT");
        require(nftPayout == 0, "nftPayout_INCORRECT");

        // Participant data checks
        (address participant, uint256 tokenId) = game.getDuelParticipant(duelID, 0);

        require(participant == address(0xABCD), "address_ERROR");
        require(tokenId == 1, "tokenId_ERROR");

        (participant, tokenId) = game.getDuelParticipant(duelID, 1);

        require(participant == address(0xBEEF), "address_ERROR");
        require(tokenId == 2, "tokenId_ERROR");

        // Contract state checks
        require(token.balanceOf(address(game)) == 0, "balanceOf_INCORRECT");
        if (winner == address(0xABCD)) {
            require(token.balanceOf(address(0xABCD)) == etherToWei(110), "balanceOf_INCORRECT");
            require(token.balanceOf(address(0xBEEF)) == etherToWei(90), "balanceOf_INCORRECT");
        } else {
            require(token.balanceOf(address(0xABCD)) == etherToWei(90), "balanceOf_INCORRECT");
            require(token.balanceOf(address(0xBEEF)) == etherToWei(110), "balanceOf_INCORRECT");
        }
        require(game.nishibBalances(address(0xABCD)) == 0, "nishibBalances_INCORRECT");
        require(game.nishibBalances(address(0xBEEF)) == 0, "nishibBalances_INCORRECT");
    }
}