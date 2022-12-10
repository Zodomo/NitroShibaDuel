// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// IMPORTANT: PROPERLY HANDLE $NISHIB TX FEE

import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";
import "openzeppelin-contracts/utils/Address.sol";
import "openzeppelin-contracts/utils/Counters.sol";

contract NitroShibaDuel is Ownable {

    /*//////////////////////////////////////////////////////////////
                LIBRARY MODIFICATIONS
    //////////////////////////////////////////////////////////////*/

    using Address for address;
    using Counters for Counters.Counter;

    /*//////////////////////////////////////////////////////////////
                CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotOwner(address sender, address owner, uint256 tokenId);
    error NotApproved(address sender, address tokenAddress);
    error NotInitiator(address sender, address initiator, uint256 duelID);
    error NotParticipant(address candidate, uint256 duelID);
    error NotWinner(address sender, address winner, uint256 duelID);
    error NotEnoughParticipants(uint256 duelID);
    error NoWinner(uint256 duelID);
    error NoSalt(uint256 duelID);

    error InvalidStatus(uint256 duelID, Status current);
    error DuelDeadline(uint256 duelID, uint256 timestamp, uint256 deadline);
    error ImproperJackpotInitialization();
    error BetBelowThreshold(uint256 bet, uint256 threshold);
    error InsufficientBalance(address sender, uint256 required, uint256 balance);
    error InvalidRecipient(address operator, address from, uint256 tokenId, bytes data);
    error TransferFailed(address sender, address recipient, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                EVENTS
    //////////////////////////////////////////////////////////////*/

    event DuelInitiated(address indexed initiator, uint256 indexed duelID);
    event DuelCanceled(address indexed initiator, uint256 indexed duelID);
    event DuelPotWithdrawn(address indexed recipient, uint256 indexed duelID, uint256 indexed pot);
    event DuelSaltGenerated(uint256 duelID, bytes32 vrfSalt);

    event TokenTransfer(address indexed from, address indexed to, uint256 indexed amount);
    event NFTTransfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /*//////////////////////////////////////////////////////////////
                STORAGE
    //////////////////////////////////////////////////////////////*/

    // Token and NFT contract addresses
    // Immutable to prevent any changes whatsoever
    address immutable nishibToken = 0x4DAD357726b41bb8932764340ee9108cC5AD33a0;
    address immutable nishibNFT = 0x74B8e48823658af4296814a8eC6baf271BcFa1e0;

    // Incremential duel count value is used as duel identifier
    Counters.Counter public duelCount;
    // Incremental $NISHIB payout total
    Counters.Counter public totalPayout;

    // Minimum bet
    uint256 public minimumBet;
    // Duel expiry timestamp
    uint256 public duelExpiry;

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
        PotPaid,
        Canceled
    }

    // Duel struct handles interaction and match data
    struct Duel {
        address[] addresses; // Player addresses, first is initiator
        uint256[] tokenIDs; // Player NFT tokenIDs, one per player, indexed by player address
        uint256 bet; // Static $NISHIB bet per player
        Mode mode; // Game mode
        Status status; // Game status
        uint256 deadline; // Duel deadline timestamp
        bytes32[] vrfInput; // Initial VRF bytes32 input per player
        bytes32 vrfSalt; // VRF salt calculated from hash of all vrfInputs
        uint256[] vrfOutput; // Output VRF numbers calculated from hash of player vrfInput + vrfSalt
        address winner; // Winner address
        uint256 participantCount; // Count of participants
        uint256 tokenPayout; // Total $NISHIB payout
        uint256 nftPayout; // NFT payout, if any
    }
    // uint256 count as duel identifier to Duel struct
    mapping(uint256 => Duel) public duels;

    /*//////////////////////////////////////////////////////////////
                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
    
    }

    /*//////////////////////////////////////////////////////////////
                IERC721Receiver
    //////////////////////////////////////////////////////////////*/

    // Is this really needed? Unsure. Keeping code until I am.

    /* function _checkOnERC721Received(
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
    } */

    /*//////////////////////////////////////////////////////////////
                DATA RETRIEVAL
    //////////////////////////////////////////////////////////////*/

    // Get total duel count
    function getDuelCount() external view returns (uint256) {
        return Counters.current(duelCount);
    }

    // Get total payout
    function getTotalPayout() external view returns (uint256) {
        return Counters.current(totalPayout);
    }

    /*//////////////////////////////////////////////////////////////
                MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // Allows contract owner to change the minimum bet
    function changeMinimumBet_(uint256 _minimumBet) public onlyOwner {
        minimumBet = _minimumBet;
    }
    
    // Allows contract owner to change the duel expiry deadline
    function changeDuelExpiry_(uint256 _duelExpiry) public onlyOwner {
        duelExpiry = _duelExpiry;
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
                sender: _sender,
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

    // Confirm duel is not expired
    function _confirmDeadline(uint256 _duelID) internal view {
        // Check if duel deadline hasn't been reached yet
        if (duels[_duelID].deadline > block.timestamp) {
            revert DuelDeadline({
                duelID: _duelID,
                timestamp: block.timestamp,
                deadline: duels[_duelID].deadline
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

    // Confirm if caller is a duel participant
    function _confirmParticipant(address _candidate, uint256 _duelID) internal view returns (uint256 tokenId) {
        // Store whether _candidate is found to trip error condition if necessary
        bool found;

        // Loop through all duel participants trying to find _candidate address
        for (uint i = 0; i < duels[_duelID].participantCount; i++) {
            // If _candidate found, return their Duels data index value
            if (duels[_duelID].addresses[i] == _candidate) {
                found = true;
                return i; // Return will end loop
            }
        }

        // Throw error if not found
        if (!found) {
            revert NotParticipant({
                candidate: _candidate,
                duelID: _duelID
            });
        }
    }
    
    // Confirm the caller is the duel winner
    function _confirmWinner(uint256 _duelID) internal view returns (address winner) {
        // Retrieve winner
        winner = duels[_duelID].winner;

        // Confirm duel has a winner
        if (winner == address(0x0)) {
            revert NoWinner({ duelID: _duelID });
        }

        // Confirm winner is msg.sender
        if (duels[_duelID].winner != msg.sender) {
            revert NotWinner({
                sender: msg.sender,
                winner: duels[_duelID].winner,
                duelID: _duelID
            });
        }

        return winner;
    }

    /*//////////////////////////////////////////////////////////////
                VRF LOGIC
    //////////////////////////////////////////////////////////////*/

    // Generate duelee's initial VRF hash
    function _vrfGenerateInput(address _duelee, uint256 _duelID) internal view returns (bytes32 vrfHash) {
        // Find _duelee's Duel data index hash, if they're a valid duelee
        uint256 index = _confirmParticipant(_duelee, _duelID);

        // Generate initial VRF hash with Duel data and mined block data
        // Multiple parameters is expensive but makes MEV nearly impossible
        vrfHash = keccak256(abi.encodePacked(
            _duelID,
            duels[_duelID].addresses[index],
            duels[_duelID].tokenIDs[index],
            duels[_duelID].bet,
            duels[_duelID].mode,
            duels[_duelID].participantCount,
            duels[_duelID].tokenPayout,
            block.number,
            block.timestamp,
            block.difficulty
        ));

        return vrfHash;
    }

    // Generate combined VRF hash salt for use in calculating duelees' vrfOutputs
    function _vrfGenerateSalt(uint256 _duelID) internal returns (bytes32 vrfSalt) {
        // Require at least two participants as that is minimum edge case
        if (duels[_duelID].participantCount > 1) {
            revert NotEnoughParticipants({ duelID: _duelID });
        }

        // Jackpot mode is the only mode that may not have just two participants
        // If in Jackpot mode, confirm deadline hasn't been reached
        if (duels[_duelID].mode == Mode.Jackpot) {
            // Throw error if jackpot deadline has not been reached
            if (duels[_duelID].deadline > block.timestamp) {
                revert DuelDeadline({
                    duelID: _duelID,
                    timestamp: block.timestamp,
                    deadline: duels[_duelID].deadline
                });
            }
        }

        // Iteratively regenerate vrfSalt using each vrfInput hash
        // I hope MEV bot operators are crying by this point
        // Last iteration will be final vrfSalt hash
        for (uint i = 0; i < duels[_duelID].participantCount; i++) {
            duels[_duelID].vrfSalt = keccak256(abi.encodePacked(
                duels[_duelID].vrfSalt,
                duels[_duelID].vrfInput[i],
                block.number,
                block.timestamp,
                block.difficulty
            ));
        }

        emit DuelSaltGenerated(_duelID, vrfSalt);

        return vrfSalt;
    }

    // Generate final VRF hash output converted to uint256 for each user
    function _vrfGenerateOutput(uint256 _duelID) internal {
        // Confirm duel vrfSalt was created
        if (duels[_duelID].vrfSalt == bytes32(0)) {
            revert NoSalt({ duelID: _duelID });
        }

        // Calculate all participants' vrfOutputs
        for (uint i = 0; i < duels[_duelID].participantCount; i++) {
            // Hash vrfSalt hash with vrfInput hash
            bytes32 saltedOutput = keccak256(abi.encodePacked(
                duels[_duelID].vrfSalt,
                duels[_duelID].vrfInput[i],
                block.number,
                block.timestamp,
                block.difficulty
            ));
            
            // Cast saltedOutput to uint256 number
            uint256 saltedNum = uint256(saltedOutput);

            // Store vrfOutput
            duels[_duelID].vrfOutput.push(saltedNum);
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
    ) internal returns (bool success) {
        // Revert if transfer fails
        success = IERC20(nishibToken).transferFrom(_from, _to, _amount);
        if (!success) {
            revert TransferFailed({
                sender: _from,
                recipient: _to,
                amount: _amount
            });
        }

        emit TokenTransfer(_from, _to, _amount);

        return success;
    }

    // Internal duel initialization logic
    // Cannot be used to initialize Jackpot duels
    function _initializeDuel(
        address _initializer,
        uint256 _tokenId,
        uint256 _bet,
        Mode _mode
    ) internal returns (uint256 _duelID) {
        // Prevent function from initializing a jackpot
        if (_mode == Mode.Jackpot) {
            revert ImproperJackpotInitialization();
        }

        // Prevent bids below minimum
        if (_bet < minimumBet) {
            revert BetBelowThreshold({
                bet: _bet,
                threshold: minimumBet
            });
        }

        // Grab current duelID
        _duelID = Counters.current(duelCount);

        // Confirm duel has not been initialized
        if (duels[_duelID].status != Status.Pending) {
            revert InvalidStatus({
                duelID: _duelID,
                current: duels[_duelID].status
            });
        }

        // Pack Duel struct
        duels[_duelID].addresses.push(_initializer);
        duels[_duelID].tokenIDs.push(_tokenId);
        duels[_duelID].bet = _bet;
        duels[_duelID].mode = _mode;
        duels[_duelID].status = Status.Initialized;
        duels[_duelID].deadline = block.timestamp + duelExpiry;
        duels[_duelID].participantCount += 1;
        duels[_duelID].tokenPayout += _bet;

        // Transfer initializer's bet to contract
        _transferToken(_initializer, address(this), _bet);

        // Generate initial VRF hash
        duels[_duelID].vrfInput.push(_vrfGenerateInput(_initializer, _duelID));

        // Increment sender's total balance stored in contract
        nishibBalances[_initializer] += _bet;
        // Increment duelCount
        Counters.increment(duelCount);

        emit DuelInitiated(_initializer, _duelID);

        return _duelID;
    }

    // Internal duel cancelation logic
    function _cancelDuel(uint256 _duelID) internal returns (bool success) {
        // Store initiator address so we can use it after destroying data if needed
        address initiator = duels[_duelID].addresses[0];

        // Loop to process withdrawals for all potential parties
        for (uint i = 0; i < duels[_duelID].participantCount; i++) {
            // Retrieve refundee address and refund value
            address refundee = duels[_duelID].addresses[i];
            uint256 refund = duels[_duelID].bet;

            // Reduce user's and duel's stored contract balance
            nishibBalances[refundee] -= refund;
            duels[_duelID].tokenPayout -= refund;

            // Process refund
            success = _transferToken(address(this), refundee, refund);
        }

        // Alter duel struct to reflect cancelation
        duels[_duelID].status = Status.Canceled;

        emit DuelCanceled(initiator, _duelID);

        return success;
    }

    function _withdrawDuel(uint256 _duelID, address _recipient) internal returns (bool success) {
        // Retrieve pot
        uint256 pot = duels[_duelID].tokenPayout;

        // Process withdrawal logic
        success = _transferToken(address(this), _recipient, pot);

        // Update Duel Status
        duels[_duelID].status = Status.PotPaid;

        emit DuelPotWithdrawn(_recipient, _duelID, pot);

        // Increment total payout via pot
        Counters.increment(totalPayout);

        return success;
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
        // Confirm Duel Status is valid for cancelation
        if (duels[_duelID].status != Status.Initialized) {
            revert InvalidStatus({
                duelID: _duelID,
                current: duels[_duelID].status
            });
        }

        // Prevent cancelation of duel if expiry deadline is not reached
        // Expiry is enforced to prevent MEV attacks
        _confirmDeadline(_duelID);

        // Confirm sender is duel initiator
        _confirmInitiator(_duelID);

        // Run internal duel cancellation logic
        success = _cancelDuel(_duelID);

        return success;
    }

    // Public function to allow duel winner to withdraw pot
    function withdrawDuel(uint256 _duelID) public returns (bool success) {
        // Confirm Duel Status is valid for withdrawal
        if (duels[_duelID].status != Status.Completed) {
            revert InvalidStatus({
                duelID: _duelID,
                current: duels[_duelID].status
            });
        }

        // Confirm sender is duel winner
        address winner = _confirmWinner(_duelID);

        success = _withdrawDuel(_duelID, winner);

        return success;
    }
}