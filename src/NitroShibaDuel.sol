// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";
import "openzeppelin-contracts/utils/Address.sol";
import "openzeppelin-contracts/utils/Counters.sol";

contract NitroShibaDuel is Ownable {

    using Address for address;
    using Counters for Counters.Counter;

    error BetBelowThreshold(uint256 bet, uint256 threshold);
    error InsufficientBalance(address sender, uint256 required, uint256 balance);
    error InvalidRecipient(address operator, address from, uint256 tokenId, bytes data);
    error DuelStatus(uint256 duelID, Status status);
    error TransferFailed(address sender, address recipient, uint256 amount);

    error NotOwner(address sender, address owner, uint256 tokenId);
    error NotApproved(address sender, address tokenAddress);
    error NotInitiator(address sender, address initiator, uint256 duelID);

    event DuelInitiated(address initiator, uint256 duelID);
    event DuelCanceled(address initiator, uint256 duelID);
    event TokenTransfer(address from, address to, uint256 amount);
    event NFTTransfer(address from, address to, uint256 tokenId);

    /*//////////////////////////////////////////////////////////////
                STORAGE
    //////////////////////////////////////////////////////////////*/

    // Token and NFT contract addresses
    // Immutable to prevent any changes whatsoever
    address immutable nishibToken = 0x4DAD357726b41bb8932764340ee9108cC5AD33a0;
    address immutable nishibNFT = 0x74B8e48823658af4296814a8eC6baf271BcFa1e0;

    // Incremential duel count value is used as duel identifier
    Counters.Counter public duelCount;
    // Minimum bet
    uint256 public minimumBet;

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
        Initialized,
        Completed,
        Canceled
    }

    // Duel struct handles interaction and match data
    struct Duel {
        address[] addresses; // Player addresses, first is initiator
        uint256[] tokenIDs; // Player NFT tokenIDs, one per player, indexed by player address
        uint256 bet; // Static $NISHIB bet per player
        Mode mode; // Game mode
        Status status; // Game status
        uint256[] outcomes; // Player VRF outcome values, highest always wins
        address winner; // Winner address
        uint256 tokenPayout; // Total $NISHIB payout
        uint256 nftPayout; // NFT payout, if any
    }
    // uint256 count as duel identifier to Duel struct
    mapping(uint256 => Duel) public duels;

    // uint256 duelId to address mapping to make initiator checks easier
    mapping(uint256 => address) public initiators;

    /*//////////////////////////////////////////////////////////////
                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {

    }

    /*//////////////////////////////////////////////////////////////
                IERC721Receiver
    //////////////////////////////////////////////////////////////*/

    function _checkOnERC721Received(
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory _data
    ) private returns (bool) {
        if (_to.isContract()) {
            try IERC721Receiver(_to).onERC721Received(msg.sender, _from, _tokenId, _data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert InvalidRecipient({
                        operator: msg.sender,
                        from: _from,
                        tokenId: _tokenId,
                        data: _data
                    });
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
                MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // Allows contract owner to change the minimum bet
    function changeMinimumBet_(uint256 _minimumBet) public onlyOwner {
        minimumBet = _minimumBet;
    }

    /*//////////////////////////////////////////////////////////////
                INTERNAL CHECKS
    //////////////////////////////////////////////////////////////*/

    // Confirm we have token approval and ownership
    function _confirmToken(address _sender, uint256 _value) internal view {
        // Ownership/Balance check
        if (IERC20(nishibToken).balanceOf(_sender) < _value) {
            revert InsufficientBalance({
                sender: _sender,
                required: _value,
                balance: IERC20(nishibToken).balanceOf(_sender)
            });
        }

        // Approval check
        if (IERC20(nishibToken).allowance(_sender, address(this)) < _value) {
            revert NotApproved({
                sender: _sender,
                tokenAddress: nishibToken
            });
        }
    }

    // Confirm we have NFT approval and ownership
    function _confirmNFT(address _sender, uint256 _tokenId) internal view {
        // Ownership check
        if (IERC721(nishibNFT).ownerOf(_tokenId) != _sender) {
            revert NotOwner({
                sender: msg.sender,
                owner: IERC721(nishibNFT).ownerOf(_tokenId),
                tokenId: _tokenId
            });
        }

        // Approval check
        if (IERC721(nishibNFT).getApproved(_tokenId) != address(this) ||
            IERC721(nishibNFT).isApprovedForAll(_sender, address(this)) == false) {
                revert NotApproved({
                    sender: _sender,
                    tokenAddress: nishibNFT
                });
            }
    }

    // Confirm the caller is the initiator
    function _confirmInitiator(uint256 _duelID) internal view {
        // Initiator check
        if (duels[_duelID].addresses[0] != msg.sender) {
            revert NotInitiator({
                sender: msg.sender,
                initiator: duels[_duelID].addresses[0],
                duelID: _duelID
            });
        }
    }

    /*//////////////////////////////////////////////////////////////
                INTERNAL DUEL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // Internal token transfer logic
    function _transferToken(
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        // Revert if transfer fails
        bool success = IERC20(nishibToken).transferFrom(_from, _to, _amount);
        if (!success) {
            revert TransferFailed({
                sender: _from,
                recipient: _to,
                amount: _amount
            });
        }

        emit TokenTransfer(_from, _to, _amount);
    }

    // Internal duel initialization logic
    function _initializeDuel(
        address _initializer,
        uint256 _tokenId,
        uint256 _bet,
        Mode _mode
    ) internal returns (uint256 _duelID) {
        // Prevent bids below minimum
        if (_bet < minimumBet) {
            revert BetBelowThreshold({
                bet: _bet,
                threshold: minimumBet
            });
        }

        // Grab current duelID
        _duelID = Counters.current(duelCount);

        // Confirm duel has not been completed or canceled
        if (duels[_duelID].status != Status.Pending) {
            revert DuelStatus({
                duelID: _duelID,
                status: duels[_duelID].status
            });
        }

        // Set initiator of duel
        initiators[_duelID] = _initializer;

        // Pack Duel struct
        duels[_duelID].addresses.push(_initializer);
        duels[_duelID].tokenIDs.push(_tokenId);
        duels[_duelID].bet = _bet;
        duels[_duelID].mode = _mode;
        duels[_duelID].status = Status.Initialized;

        // Increment duelCount
        Counters.increment(duelCount);

        // Transfer initializer's bet to contract
        _transferToken(_initializer, address(this), _bet);
        // Increment sender's total balance stored in contract
        nishibBalances[_initializer] += _bet;

        emit DuelInitiated(_initializer, _duelID);

        return _duelID;
    }

    // TODO: Cancelation logic
    function _cancelDuel(uint256 _duelID) internal returns (bool success) {
        address initiator = duels[_duelID].addresses[0];
        // Cancelation logic

        emit DuelCanceled(initiator, _duelID);

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                PUBLIC DUEL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // Public function to initiate a duel instance
    function initiateDuel(
        uint256 _tokenId,
        uint256 _bet,
        Mode _mode
    ) public returns (uint256 _duelID) {
        // Confirm token and NFT approvals and ownership
        _confirmToken(msg.sender, _bet);
        _confirmNFT(msg.sender, _tokenId);

        // Initialize Duel struct
        _duelID = _initializeDuel(msg.sender, _tokenId, _bet, _mode);

        return _duelID;
    }

    // Public function allowing the initiator to cancel a duel
    function cancelDuel(uint256 _duelID) public returns (bool success) {
        // Confirm sender is duel initiator
        _confirmInitiator(_duelID);

        // Run internal duel cancellation logic
        success = _cancelDuel(_duelID);

        return success;
    }
}