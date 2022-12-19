// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {DSInvariantTest} from "solmate/test/utils/DSInvariantTest.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC721} from "solmate/test/utils/mocks/MockERC721.sol";
import {ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import {Counters} from "openzeppelin-contracts/utils/Counters.sol";

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
            etherToWei(5),
            etherToWei(50),
            0,
            0
        );
        hevm.prank(address(game));
        nft.setApprovalForAll(address(game), true);

        // Mint 0xABCD and 0xBEEF 100 tokens
        token.mint(address(0xABCD), etherToWei(100));
        token.mint(address(0xBEEF), etherToWei(100));

        // Mint 0xABCD and 0xBEEF 3 NFTs
        nft.mint(address(0xABCD), 1);
        nft.mint(address(0xBEEF), 2);
        nft.mint(address(0xABCD), 3);
        nft.mint(address(0xBEEF), 4);

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

        // Bulk account prep
        for (uint160 i = 1; i <= 1000; i++) {
            token.mint(address(i), etherToWei(100));
            nft.mint(address(i), i * 100);
            nft.mint(address(i), (i * 100) + 1);

            hevm.startPrank(address(i));
            token.approve(address(game), etherToWei(100));
            nft.setApprovalForAll(address(game), true);
            hevm.stopPrank();
        }
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
        (address participant, uint256 tokenId, bytes32 vrfHash) = game.getDuelParticipant(duelID, 0);

        require(participant == address(0xABCD), "address_INCORRECT");
        require(tokenId == 1, "tokenId_INCORRECT");
        require(vrfHash != bytes32(0x0), "vrfInput_INCORRECT");

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
        (address participant, uint256 tokenId, bytes32 vrfHash) = game.getDuelParticipant(duelID, 0);

        require(participant == address(0xABCD), "address_ERROR");
        require(tokenId == 1, "tokenId_ERROR");
        require(vrfHash != bytes32(0x0), "vrfInput_INCORRECT");

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
        (address participant, uint256 tokenId, bytes32 vrfHash) = game.getDuelParticipant(duelID, 0);

        require(participant == address(0xABCD), "address_ERROR");
        require(tokenId == 1, "tokenId_ERROR");
        require(vrfHash != bytes32(0x0), "vrfInput_INCORRECT");

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
        (address participant, uint256 tokenId, bytes32 vrfHash) = game.getDuelParticipant(duelID, 0);

        require(participant == address(0xABCD), "address_ERROR");
        require(tokenId == 1, "tokenId_ERROR");
        require(vrfHash != bytes32(0x0), "vrfInput_INCORRECT");

        (participant, tokenId, vrfHash) = game.getDuelParticipant(duelID, 1);

        require(participant == address(0xBEEF), "address_ERROR");
        require(tokenId == 2, "tokenId_ERROR");
        require(vrfHash != bytes32(0x0), "vrfInput_INCORRECT");

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
        (address participant, uint256 tokenId, bytes32 vrfHash) = game.getDuelParticipant(duelID, 0);

        require(participant == address(0xABCD), "address_ERROR");
        require(tokenId == 1, "tokenId_ERROR");
        require(vrfHash != bytes32(0x0), "vrfInput_INCORRECT");

        (participant, tokenId, vrfHash) = game.getDuelParticipant(duelID, 1);

        require(participant == address(0xBEEF), "address_ERROR");
        require(tokenId == 2, "tokenId_ERROR");
        require(vrfHash != bytes32(0x0), "vrfInput_INCORRECT");

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
        (address participant, uint256 tokenId, bytes32 vrfHash) = game.getDuelParticipant(duelID, 0);

        require(participant == address(0xABCD), "address_ERROR");
        require(tokenId == 1, "tokenId_ERROR");
        require(vrfHash != bytes32(0x0), "vrfInput_INCORRECT");

        (participant, tokenId, vrfHash) = game.getDuelParticipant(duelID, 1);

        require(participant == address(0xBEEF), "address_ERROR");
        require(tokenId == 2, "tokenId_ERROR");
        require(vrfHash != bytes32(0x0), "vrfInput_INCORRECT");

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
        (,,NitroShibaDuel.Status status,,,,address winner, uint256 participantCount, uint256 tokenPayout,) = game.getDuelData(duelID);

        require(status == NitroShibaDuel.Status.PotPaid, "status_INCORRECT");
        require(winner == address(0xABCD) || winner == address(0xBEEF), "winner_INCORRECT");
        require(participantCount == 2, "participantCount_INCORRECT");
        require(tokenPayout == etherToWei(20), "tokenPayout_INCORRECT");

        // Participant data checks
        (address participant, uint256 tokenId, bytes32 vrfHash) = game.getDuelParticipant(duelID, 0);

        require(participant == address(0xABCD), "address_ERROR");
        require(tokenId == 1, "tokenId_ERROR");
        require(vrfHash != bytes32(0x0), "vrfInput_INCORRECT");

        (participant, tokenId, vrfHash) = game.getDuelParticipant(duelID, 1);

        require(participant == address(0xBEEF), "address_ERROR");
        require(tokenId == 2, "tokenId_ERROR");
        require(vrfHash != bytes32(0x0), "vrfInput_INCORRECT");

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

    // Test DoubleOrNothing logic
    function testDoubleOrNothingDuel() public {
        // Initiate duel as 0xABCD
        hevm.prank(address(0xABCD));
        uint256 duelID = game.initiateDuel(1, etherToWei(10), NitroShibaDuel.Mode.SimpleBet);

        // Join duel as 0xBEEF
        hevm.prank(address(0xBEEF));
        game.joinDuel(2, duelID);

        // Execute duel as 0xABCD
        hevm.prank(address(0xABCD));
        game.executeDuel(duelID);

        // Enable DoubleOrNothing as 0xABCD
        hevm.prank(address(0xABCD));
        game.doubleOrNothingDuel(duelID, 1);

        // Enable DoubleOrNothing as 0xBEEF
        hevm.prank(address(0xBEEF));
        game.doubleOrNothingDuel(duelID, 2);

        // Standard duel data checks
        (
            uint256 bet, NitroShibaDuel.Mode mode, NitroShibaDuel.Status status,
            uint256 deadline, bytes32 vrfSalt, bytes32 vrfDONSalt,
            address winner, uint256 participantCount, uint256 tokenPayout, uint256 nftPayout
        ) = game.getDuelData(duelID);

        require(duelID == 1, "duelID_INCORRECT");
        require(bet == etherToWei(10), "bet_INCORRECT");
        require(mode == NitroShibaDuel.Mode.DoubleOrNothing, "mode_INCORRECT");
        require(status == NitroShibaDuel.Status.Completed, "status_INCORRECT");
        require(deadline > 0, "deadline_INCORRECT");
        require(vrfSalt != bytes32(0), "vrfSalt_INCORRECT");
        require(vrfDONSalt != bytes32(0), "vrfDONSalt_INCORRECT");
        require(winner == address(0xABCD) || winner == address(0xBEEF), "winner_INCORRECT");
        require(participantCount == 2, "participantCount_INCORRECT");
        require(tokenPayout == etherToWei(20), "tokenPayout_INCORRECT");
        require(nftPayout == 1 || nftPayout == 2, "nftPayout_INCORRECT");

        // Contract state checks
        require(token.balanceOf(address(game)) == etherToWei(20), "balanceOf_INCORRECT");
        require(nft.ownerOf(nftPayout) != address(game), "nftOwnership_ERROR");
        require(nft.ownerOf(nftPayout) == winner, "nftPayout_ERROR");

        // Check outcome stats
        require(game.nishibBalances(winner) == etherToWei(20), "nishibBalances_INCORRECT");
    }

    // Test withdrawing from a double or nothing round
    function testWithdrawAfterDoubleOrNothing() public {
        // Initiate duel as 0xABCD
        hevm.prank(address(0xABCD));
        uint256 duelID = game.initiateDuel(1, etherToWei(10), NitroShibaDuel.Mode.SimpleBet);

        // Join duel as 0xBEEF
        hevm.prank(address(0xBEEF));
        game.joinDuel(2, duelID);

        // Execute duel as 0xABCD
        hevm.prank(address(0xABCD));
        game.executeDuel(duelID);

        // Enable DoubleOrNothing as 0xABCD
        hevm.prank(address(0xABCD));
        game.doubleOrNothingDuel(duelID, 1);

        // Enable DoubleOrNothing as 0xBEEF
        hevm.prank(address(0xBEEF));
        game.doubleOrNothingDuel(duelID, 2);

        // Attempt withdrawal as winner
        (,,,,,,address duelWinner,,,) = game.getDuelData(duelID);
        hevm.prank(duelWinner);
        game.withdrawDuel(duelID);

        // Confirm withdrawal took place
        require(token.balanceOf(duelWinner) == etherToWei(110), "balanceOf_INCORRECT");
        require(game.nishibBalances(address(0xABCD)) == 0, "nishibBalances_INCORRECT");
        require(game.nishibBalances(address(0xBEEF)) == 0, "nishibBalances_INCORRECT");
    }

    // Test joining uninitialized duel
    function testFailJoinUninitializedDuel() public {
        hevm.prank(address(0xABCD));
        game.joinDuel(1, 1);
    }

    // Test canceling uninitialized duel
    function testFailCancelUninitializedDuel() public {
        hevm.prank(address(0xABCD));
        game.cancelDuel(1);
    }

    // Test enabling DON on uninitialized duel
    function testFailDoubleOrNothingUninitializedDuel() public {
        hevm.prank(address(0xABCD));
        game.doubleOrNothingDuel(1, 1);
    }

    // Test executing uninitialized duel
    function testFailExecuteUninitializedDuel() public {
        hevm.prank(address(0xABCD));
        game.executeDuel(1);
    }

    // Test withdrawing uninitialized duel
    function testFailWithdrawUninitializedDuel() public {
        hevm.prank(address(0xABCD));
        game.withdrawDuel(1);
    }

    // Test joining duelID 0
    function testFailJoinZeroDuel() public {
        hevm.prank(address(0xABCD));
        game.joinDuel(1, 0);
    }

    // Test canceling duelID 0
    function testFailCancelZeroDuel() public {
        hevm.prank(address(0xABCD));
        game.cancelDuel(0);
    }

    // Test enabling DON on duelID 0
    function testFailDoubleOrNothingZeroDuel() public {
        hevm.prank(address(0xABCD));
        game.doubleOrNothingDuel(0, 1);
    }

    // Test executing duelID 0
    function testFailExecuteZeroDuel() public {
        hevm.prank(address(0xABCD));
        game.executeDuel(0);
    }

    // Test withdrawing duelID 0
    function testFailWithdrawZeroDuel() public {
        hevm.prank(address(0xABCD));
        game.withdrawDuel(0);
    }

    // Test initiating a duel without owning the proposed NFT
    function testFailInitiateDuelWithoutNFTOwnership() public {
        hevm.prank(address(0xABCD));
        game.initiateDuel(2, etherToWei(10), NitroShibaDuel.Mode.SimpleBet);
    }

    // Test initiating a duel with a bet higher than user's balance
    function testFailInitiateDuelWithBetAboveBalance() public {
        hevm.prank(address(0xABCD));
        game.initiateDuel(1, etherToWei(101), NitroShibaDuel.Mode.SimpleBet);
    }

    // Test initiating a duel with a bet below the minimum
    function testFailInitiateDuelWithBetBelowMinimum() public {
        hevm.prank(address(0xABCD));
        game.initiateDuel(1, etherToWei(1), NitroShibaDuel.Mode.SimpleBet);
    }

    // Test initiating a duel with a bet below the maximum
    function testFailInitiateDuelWithBetAboveMaximum() public {
        hevm.prank(address(0xABCD));
        game.initiateDuel(1, etherToWei(100), NitroShibaDuel.Mode.SimpleBet);
    }

    // Test bulk contract initiation
    function testBulk10InitiateDuel() public {
        // Bulk initiate duels
        for (uint160 i = 1; i <= 10; i++) {
            hevm.prank(address(i));
            game.initiateDuel(i * 100, etherToWei(10), NitroShibaDuel.Mode.SimpleBet);
        }

        // Contract state checks
        require(game.duelIndex() == 11, "duelIndex_INCORRECT");
        require(token.balanceOf(address(game)) == etherToWei(100), "balanceOf_INCORRECT");

        // Check all duel data
        for (uint160 j = 1; j <= 10; j++) {
            // Standard duel data checks
            (
                uint256 bet, NitroShibaDuel.Mode mode, NitroShibaDuel.Status status,
                uint256 deadline, bytes32 vrfSalt, bytes32 vrfDONSalt,
                address winner, uint256 participantCount, uint256 tokenPayout,
            ) = game.getDuelData(j);

            require(bet == etherToWei(10), "bet_INCORRECT");
            require(mode == NitroShibaDuel.Mode.SimpleBet, "mode_INCORRECT");
            require(status == NitroShibaDuel.Status.Initialized, "status_INCORRECT");
            require(deadline > 0, "deadline_INCORRECT");
            require(vrfSalt == bytes32(0), "vrfSalt_INCORRECT");
            require(vrfDONSalt == bytes32(0), "vrfDONSalt_INCORRECT");
            require(winner == address(0), "winner_INCORRECT");
            require(participantCount == 1, "participantCount_INCORRECT");
            require(tokenPayout == etherToWei(10), "tokenPayout_INCORRECT");

            // Participant data checks
            (address participant, uint256 tokenId, bytes32 vrfHash) = game.getDuelParticipant(j, 0);

            require(participant == address(j), "address_INCORRECT");
            require(tokenId == j * 100, "tokenId_INCORRECT");
            require(vrfHash != bytes32(0x0), "vrfInput_INCORRECT");

            // Contract state checks
            require(game.nishibBalances(address(j)) == etherToWei(10), "nishibBalances_INCORRECT");
        }
    }

    // Test bulk contract cancelation
    function testBulk10CancelDuel() public {
        // Bulk initiate duels
        for (uint160 i = 1; i <= 10; i++) {
            hevm.prank(address(i));
            game.initiateDuel(i * 100, etherToWei(10), NitroShibaDuel.Mode.SimpleBet);
        }

        // Bulk cancel duels
        for (uint160 i = 1; i <= 10; i++) {
            hevm.prank(address(i));
            game.cancelDuel(i);
        }

        // Contract state checks
        require(game.duelIndex() == 11, "duelIndex_INCORRECT");
        require(token.balanceOf(address(game)) == 0, "balanceOf_INCORRECT");

        // Check all duel data
        for (uint160 j = 1; j <= 10; j++) {
            // Standard duel data checks
            (
                uint256 bet, NitroShibaDuel.Mode mode, NitroShibaDuel.Status status,
                uint256 deadline, bytes32 vrfSalt, bytes32 vrfDONSalt,
                address winner, uint256 participantCount, uint256 tokenPayout,
            ) = game.getDuelData(j);

            require(bet == etherToWei(10), "bet_INCORRECT");
            require(mode == NitroShibaDuel.Mode.SimpleBet, "mode_INCORRECT");
            require(status == NitroShibaDuel.Status.Canceled, "status_INCORRECT");
            require(deadline > 0, "deadline_INCORRECT");
            require(vrfSalt == bytes32(0), "vrfSalt_INCORRECT");
            require(vrfDONSalt == bytes32(0), "vrfDONSalt_INCORRECT");
            require(winner == address(0), "winner_INCORRECT");
            require(participantCount == 1, "participantCount_INCORRECT");
            require(tokenPayout == 0, "tokenPayout_INCORRECT");

            // Participant data checks
            (address participant, uint256 tokenId, bytes32 vrfHash) = game.getDuelParticipant(j, 0);

            require(participant == address(j), "address_INCORRECT");
            require(tokenId == j * 100, "tokenId_INCORRECT");
            require(vrfHash != bytes32(0x0), "vrfInput_INCORRECT");

            // Contract state checks
            require(game.nishibBalances(address(j)) == 0, "nishibBalances_INCORRECT");
        }
    }

    // Test bulk contract join
    function testBulk10JoinDuel() public {
        // Initiate duel as 0xABCD
        hevm.prank(address(0xABCD));
        uint256 duelID = game.initiateDuel(1, etherToWei(10), NitroShibaDuel.Mode.SimpleBet);

        // Bulk join duel
        for (uint160 i = 1; i <= 10; i++) {
            hevm.prank(address(i));
            game.joinDuel(i * 100, duelID);
        }

        // Check participant data
        for (uint160 j = 1; j <= 10; j++) {
            (address participant, uint256 tokenId, bytes32 vrfHash) = game.getDuelParticipant(duelID, j);

            require(participant == address(j), "address_INCORRECT");
            require(tokenId == j * 100, "tokenId_INCORRECT");
            require(vrfHash != bytes32(0x0), "vrfInput_INCORRECT");
            require(game.nishibBalances(address(j)) == etherToWei(10), "nishibBalances_INCORRECT");
        }

        // Standard duel data checks
        (
            uint256 bet, NitroShibaDuel.Mode mode, NitroShibaDuel.Status status,
            uint256 deadline, bytes32 vrfSalt, bytes32 vrfDONSalt,
            address winner, uint256 participantCount, uint256 tokenPayout,
        ) = game.getDuelData(duelID);

        require(bet == etherToWei(10), "bet_INCORRECT");
        require(mode == NitroShibaDuel.Mode.SimpleBet, "mode_INCORRECT");
        require(status == NitroShibaDuel.Status.Initialized, "status_INCORRECT");
        require(deadline > 0, "deadline_INCORRECT");
        require(vrfSalt == bytes32(0), "vrfSalt_INCORRECT");
        require(vrfDONSalt == bytes32(0), "vrfDONSalt_INCORRECT");
        require(winner == address(0), "winner_INCORRECT");
        require(participantCount == 11, "participantCount_INCORRECT");
        require(tokenPayout == etherToWei(110), "tokenPayout_INCORRECT");
        require(token.balanceOf(address(game)) == etherToWei(110), "balanceOf_INCORRECT");
    }

    // Test contract execution after bulk join
    function testBulk10ExecuteDuel() public {
        // Initiate duel as 0xABCD
        hevm.prank(address(0xABCD));
        uint256 duelID = game.initiateDuel(1, etherToWei(10), NitroShibaDuel.Mode.SimpleBet);

        // Bulk join duel
        for (uint160 i = 1; i <= 10; i++) {
            hevm.prank(address(i));
            game.joinDuel(i * 100, duelID);
        }

        // Execute duel as 0xABCD
        hevm.prank(address(0xABCD));
        game.executeDuel(duelID);

        // Standard duel data checks
        (
            uint256 bet, NitroShibaDuel.Mode mode, NitroShibaDuel.Status status,
            uint256 deadline, bytes32 vrfSalt, bytes32 vrfDONSalt,
            address winner, uint256 participantCount, uint256 tokenPayout,
        ) = game.getDuelData(duelID);

        require(bet == etherToWei(10), "bet_INCORRECT");
        require(mode == NitroShibaDuel.Mode.SimpleBet, "mode_INCORRECT");
        require(status == NitroShibaDuel.Status.Completed, "status_INCORRECT");
        require(deadline > 0, "deadline_INCORRECT");
        require(vrfSalt != bytes32(0), "vrfSalt_INCORRECT");
        require(vrfDONSalt == bytes32(0), "vrfDONSalt_INCORRECT");
        require(winner != address(0), "winner_INCORRECT");
        require(participantCount == 11, "participantCount_INCORRECT");
        require(tokenPayout == etherToWei(110), "tokenPayout_INCORRECT");
        require(token.balanceOf(address(game)) == etherToWei(110), "balanceOf_INCORRECT");
        require(game.nishibBalances(winner) == etherToWei(110), "nishibBalances_INCORRECT");
    }

    // Test contract execution to find gas limitations for max participants
    function testBulkMaxSimpleBetParticipation() public {
        // Initiate duel as 0xABCD
        hevm.prank(address(0xABCD));
        uint256 duelID = game.initiateDuel(1, etherToWei(10), NitroShibaDuel.Mode.SimpleBet);

        // Bulk join duel
        for (uint160 i = 1; i <= 1000; i++) {
            hevm.prank(address(i));
            game.joinDuel(i * 100, duelID);
        }

        // Execute duel as 0xABCD
        hevm.prank(address(0xABCD));
        game.executeDuel(duelID);
    }
}