// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/token/ERC721/utils/ERC721Holder.sol";
import "openzeppelin-contracts/utils/Address.sol";
import "openzeppelin-contracts/utils/Counters.sol";

contract NitroShibaDuel is Ownable, ERC721Holder {

    /*//////////////////////////////////////////////////////////////
                LIBRARY MODIFICATIONS
    //////////////////////////////////////////////////////////////*/

    using Address for address;
    using Counters for Counters.Counter;

    /*//////////////////////////////////////////////////////////////
                CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotOwner(address sender, address owner, uint256 tokenId);
    error NotApproved(address sender, address tokenAddress, uint256 amount);
    error NotInitiator(address sender, address initiator, uint256 duelID);
    error NotParticipant(address candidate, uint256 duelID);
    error NotWinner(address sender, address winner, uint256 duelID);
    error NotLoser(address sender, uint256 duelID);
    error NotEnoughParticipants(uint256 duelID);
    error NoParticipants(uint256 duelID);
    error NoWinner(uint256 duelID);
    error NoSalt(uint256 duelID);

    error InvalidStatus(uint256 duelID, Status current);
    error InvalidMode(uint256 duelID, Mode mode);
    error TooManyParticipants(uint256 duelID, uint256 required, uint256 count);
    error AlreadyJoined(uint256 duelID);
    error DuelDeadline(uint256 duelID, uint256 timestamp, uint256 deadline);
    error ImproperJackpotInitialization(uint256 jackpotIndex);
    error ImproperJackpotCancelation(uint256 duelID);
    error BetBelowThreshold(uint256 bet, uint256 threshold);
    error BetAboveThreshold(uint256 bet, uint256 threshold);
    error InsufficientBalance(address sender, address recipient, uint256 required, uint256 balance);
    error InvalidRecipient(address operator, address from, uint256 tokenId, bytes data);
    error TransferFailed(address sender, address recipient, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                EVENTS
    //////////////////////////////////////////////////////////////*/

    event DuelInitiated(address indexed initiator, uint256 indexed duelID);
    event DuelCanceled(address indexed initiator, uint256 indexed duelID);
    event DuelJoined(address indexed challenger, uint256 indexed duelID);
    event DuelExecuted(address indexed executor, address indexed winner, uint256 indexed duelID);
    event DuelSaltGenerated(uint256 indexed duelID, bytes32 indexed vrfSalt);
    event DuelDONSwitched(address indexed participant, uint256 indexed duelID);
    event DuelDONEnabled(uint256 indexed duelID);
    event DuelPotWithdrawn(address indexed recipient, uint256 indexed duelID, uint256 indexed pot);

    event TokenTransfer(address indexed from, address indexed to, uint256 indexed amount);
    event NFTTransfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /*//////////////////////////////////////////////////////////////
                STORAGE
    //////////////////////////////////////////////////////////////*/

    // Token and NFT contract addresses
    address nishibToken; // 0x4DAD357726b41bb8932764340ee9108cC5AD33a0
    address nishibNFT; // 0x74B8e48823658af4296814a8eC6baf271BcFa1e0

    // Incremential duel count value is used as duel identifier
    Counters.Counter public duelCount;
    // Incremental $NISHIB payout total
    Counters.Counter public totalPayout;
    // Current duels index for active jackpot
    uint256 public jackpotIndex;

    // Minimum bet
    uint256 public minimumBet;
    // Maximum bet
    uint256 public maximumBet;
    // Minimum duel term
    uint256 public duelExpiry;
    // Jackpot term
    uint256 public jackpotExpiry;

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
        bytes32 vrfDONSalt;
        uint256[] vrfOutput; // Output VRF numbers calculated from hash of player vrfInput + vrfSalt
        address winner; // Winner address
        mapping(address => bool) DONSwitch; // DoubleOrNothing switch, both users need to set to true
        uint256 participantCount; // Count of participants
        uint256 tokenPayout; // Total $NISHIB payout
        uint256 nftPayout; // tokenId of NFT payout, if any
    }
    // uint256 count as duel identifier to Duel struct
    mapping(uint256 => Duel) public duels;

    /*//////////////////////////////////////////////////////////////
                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _nishibToken,
        address _nishibNFT,
        uint256 _minimumBet,
        uint256 _maximumBet,
        uint256 _duelExpiry,
        uint256 _jackpotExpiry
    ) {
        // Start duels index at 1 because we don't want default values in execution
        Counters.increment(duelCount);

        nishibToken = _nishibToken; // 0x4DAD357726b41bb8932764340ee9108cC5AD33a0
        nishibNFT = _nishibNFT; // 0x74B8e48823658af4296814a8eC6baf271BcFa1e0

        minimumBet = _minimumBet;
        maximumBet = _maximumBet;
        duelExpiry = _duelExpiry;
        jackpotExpiry = _jackpotExpiry;
    }

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

    // Get Duel data
    function getDuelData(uint256 _duelID) external view returns (
        uint256 bet, Mode mode, Status status,
        uint256 deadline, bytes32 vrfSalt, bytes32 vrfDONSalt,
        address winner, uint256 participantCount, uint256 tokenPayout, uint256 nftPayout
    ) {
        bet = duels[_duelID].bet;
        mode = duels[_duelID].mode;
        status = duels[_duelID].status;
        deadline = duels[_duelID].deadline;
        vrfSalt = duels[_duelID].vrfSalt;
        vrfDONSalt = duels[_duelID].vrfDONSalt;
        winner = duels[_duelID].winner;
        participantCount = duels[_duelID].participantCount;
        tokenPayout = duels[_duelID].tokenPayout;
        nftPayout = duels[_duelID].nftPayout;
    }

    /*//////////////////////////////////////////////////////////////
                MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // Allows contract owner to change the minimum bet
    function changeMinimumBet_(uint256 _minimumBet) public onlyOwner {
        minimumBet = _minimumBet;
    }

    // Allows contract owner to change the maximum bet
    function changeMaximumBet_(uint256 _maximumBet) public onlyOwner {
        maximumBet = _maximumBet;
    }
    
    // Allows contract owner to change the duel expiry deadline
    function changeDuelExpiry_(uint256 _duelExpiry) public onlyOwner {
        duelExpiry = _duelExpiry;
    }

    // Allows contract owner to change the jackpot term
    function changeJackpotExpiry_(uint256 _jackpotExpiry) public onlyOwner {
        jackpotExpiry = _jackpotExpiry;
    }

    // Only the contract owner can cancel an initiated jackpot
    // Since any community member can initiate a jackpot, it would be considered chaotic
    // to trust random initiators to randomly cancel high-participation jackpots
    // NOTE: Contract owner cannot cancel jackpot if they participated in it
    function cancelJackpot_(uint256 _jackpotIndex) public onlyOwner {
        // Loop through all duel participants trying to find contract owner address
        for (uint i = 0; i < duels[_jackpotIndex].participantCount; i++) {
            // If contract owner address is found, throw error
            if (duels[_jackpotIndex].addresses[i] == msg.sender) {
                revert ImproperJackpotCancelation({ duelID: _jackpotIndex });
            }
        }

        // Run internal duel cancelation logic
        _cancelDuel(_jackpotIndex);
    }

    /*//////////////////////////////////////////////////////////////
                LIBRARY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // ether to wei unit conversion
    function etherToWei(uint256 _value) public pure returns (uint256) {
        return _value * (10 ** 18);
    }

    /*//////////////////////////////////////////////////////////////
                INTERNAL CHECKS
    //////////////////////////////////////////////////////////////*/

    // ****************** TODO: FIX APPROVAL CHECKING ***************************

    // Confirm we have token approval and ownership
    function _confirmToken(address _sender, uint256 _value) internal view {
        // Ownership/Balance check
        if (IERC20(nishibToken).balanceOf(_sender) < _value) {
            revert InsufficientBalance({
                sender: _sender,
                recipient: address(0x0),
                required: _value,
                balance: IERC20(nishibToken).balanceOf(_sender)
            });
        }

        // Approval check
        if (IERC20(nishibToken).allowance(_sender, address(this)) < _value) {
            revert NotApproved({
                sender: _sender,
                tokenAddress: nishibToken,
                amount: _value
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
        if (IERC721(nishibNFT).getApproved(_tokenId) == address(this)) { return; }
        else if (IERC721(nishibNFT).isApprovedForAll(_sender, address(this)) == true) { return; }
        else {
            revert NotApproved({
                sender: _sender,
                tokenAddress: nishibNFT,
                amount: 1
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

    // Confirm the caller is a valid participant but lost
    function _confirmLoser(uint256 _duelID) internal view returns (bool) {
        // Loop through all Duel participant addresses
        for (uint i = 0; i < duels[_duelID].participantCount; i++) {
            if (duels[_duelID].winner != msg.sender &&
                duels[_duelID].addresses[i] == msg.sender) {
                    return true;
            }
        }

        // If a valid loser didn't call, throw error
        revert NotLoser({
            sender: msg.sender,
            duelID: _duelID
        });
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
        // Iteratively regenerate vrfSalt using each vrfInput hash
        // I hope MEV bot operators are crying by this point
        // Last iteration will be final vrfSalt hash
        for (uint i = 0; i < duels[_duelID].participantCount; i++) {
            vrfSalt = keccak256(abi.encodePacked(
                vrfSalt,
                duels[_duelID].vrfInput[i],
                block.number,
                block.timestamp,
                block.difficulty
            ));
        }

        emit DuelSaltGenerated(_duelID, vrfSalt);

        return vrfSalt;
    }

    // Utilize vrfOutput as new input for DoubleOrNothing resalting
    function _vrfGenerateDONSalt(uint256 _duelID) internal returns (bytes32 vrfDONSalt) {
        for (uint i = 0; i < duels[_duelID].participantCount; i++) {
            vrfDONSalt = keccak256(abi.encodePacked(
                vrfDONSalt,
                duels[_duelID].vrfSalt,
                duels[_duelID].vrfInput[i],
                duels[_duelID].vrfOutput[i],
                block.number,
                block.timestamp,
                block.difficulty
            ));
        }

        emit DuelSaltGenerated(_duelID, vrfDONSalt);

        return vrfDONSalt;
    }

    // Generate final VRF hash output converted to uint256 for each user
    function _vrfGenerateOutputs(uint256 _duelID) internal {
        // Confirm duel vrfSalt was created
        if (duels[_duelID].vrfSalt == bytes32(0)) {
            revert NoSalt({ duelID: _duelID });
        }

        // If vrfDONSalt is present, overwrite vrfOutput with new DONSalted outputs
        if (duels[_duelID].vrfDONSalt != bytes32(0)) {
            for (uint i = 0; i < duels[_duelID].participantCount; i++) {
                // Hash vrfSalt hash with vrfInput hash
                bytes32 saltedOutput = keccak256(abi.encodePacked(
                    duels[_duelID].vrfSalt,
                    duels[_duelID].vrfDONSalt,
                    duels[_duelID].vrfInput[i],
                    duels[_duelID].vrfOutput[i],
                    block.number,
                    block.timestamp,
                    block.difficulty
                ));

                // Cast saltedOutput to uint256 number
                uint256 saltedNum = uint256(saltedOutput);

                // Overwrite vrfOutput
                duels[_duelID].vrfOutput[i] = saltedNum;
            }
        } else {
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
    }

    /*//////////////////////////////////////////////////////////////
                INTERNAL TRANSFER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // Internal token transfer logic
    function _transferToken(
        address _from,
        address _to,
        uint256 _amount
    ) internal returns (bool success) {
        // Prevent self-transfers
        if (_from == _to) {
            revert TransferFailed({
                sender: _from,
                recipient: _to,
                amount: _amount
            });
        }

        // Prevent transfer if contract balance is too low
        if (_from == address(this) && 
            _amount > IERC20(nishibToken).balanceOf(address(this))) {
                revert InsufficientBalance({
                    sender: _from,
                    recipient: _to,
                    required: _amount,
                    balance: IERC20(nishibToken).balanceOf(_from)
                });
        }

        // If _amount is zero, PVP mode is engaged, so skip transfer logic
        if (_amount == 0) {
            success = true;
            return success;
        }

        // Revert if transfer fails
        success = IERC20(nishibToken).transferFrom(_from, _to, _amount);
        if (!success) {
            revert TransferFailed({
                sender: _from,
                recipient: _to,
                amount: _amount
            });
        }

        // Process contract balance changes
        // Withdrawal
        if (_from == address(this)) {
            // Throw error if _from has insufficient contract balance
            if (nishibBalances[_to] < _amount) {
                revert InsufficientBalance({
                    sender: _from,
                    recipient: _to,
                    required: _amount,
                    balance: nishibBalances[_to]
                });
            }
            // Reduce contract balance for recipient
            nishibBalances[_to] -= _amount;
        }
        // Deposit
        else if (_to == address(this)) {
            nishibBalances[_from] += _amount;
        }

        emit TokenTransfer(_from, _to, _amount);

        return success;
    }

    // Internal NFT transfer logic
    function _transferNFT(
        address _from,
        address _to,
        uint256 _tokenId
    ) internal {
        // Confirm contract owns the NFT
        if (IERC721(nishibNFT).ownerOf(_tokenId) != address(this)) {
            revert NotOwner({
                sender: _from,
                owner: IERC721(nishibNFT).ownerOf(_tokenId),
                tokenId: _tokenId
            });
        }

        IERC721(nishibNFT).safeTransferFrom(_from, _to, _tokenId);

        emit NFTTransfer(_from, _to, _tokenId);
    }

    // Internal token refund logic
    function _refundTokens(uint256 _duelID) internal {
        // Loop to process withdrawals for all potential parties
        for (uint i = 0; i < duels[_duelID].participantCount; i++) {
            // Retrieve refundee address and refund value
            address refundee = duels[_duelID].addresses[i];
            uint256 refund = duels[_duelID].bet;

            // Throw error if tokenPayout is empty
            if (duels[_duelID].tokenPayout < refund) {
                revert InsufficientBalance({
                    sender: address(this),
                    recipient: refundee,
                    required: refund,
                    balance: duels[_duelID].tokenPayout
                });
            }
            // Otherwise, deduct user token refund from totalPayout
            else {
                duels[_duelID].tokenPayout -= refund;
            }

            // Process refund
            _transferToken(address(this), refundee, refund);
        }
    }

    // Internal NFT refund logic
    function _refundNFTs(uint256 _duelID) internal {
        // Loop to process withdrawals for all potential parties
        for (uint i = 0; i < duels[_duelID].participantCount; i++) {
            // Retrieve refundee address and refund value
            address refundee = duels[_duelID].addresses[i];
            uint256 tokenId = duels[_duelID].tokenIDs[i];

            // Wipe out tokenId
            duels[_duelID].tokenIDs[i] = 0;

            // Process refund
            _transferNFT(address(this), refundee, tokenId);
        }
    }

    // Internal function to reduce loser's $NISHIB contract balance
    function _adjustBalances(uint256 _duelID) internal {
        // Retrieve winner address and bet amount for code clarity
        address winner = duels[_duelID].winner;
        uint256 bet = duels[_duelID].bet;

        // Loop through all participants and transfer their bet from their balance to winner
        for (uint i = 0; i < duels[_duelID].participantCount; i++) {
            // Store loser address for cleaner code
            address loser = duels[_duelID].addresses[i];
            
            // Only process balance changes for losers
            if (loser != winner) {
                // Reduce loser's contract balance and transfer to winner
                nishibBalances[loser] -= bet;
                nishibBalances[winner] += bet;
            }
        }
    }

    // Internal function to handle DoubleOrNothing asset transfer rules
    function _adjustDONBalances(uint256 _duelID) internal {
        // Retrieve winner address, total pot, and staked NFT tokenId for code clarity
        address winner = duels[_duelID].winner;
        uint256 pot = duels[_duelID].tokenPayout;
        uint256 tokenId = duels[_duelID].nftPayout;
        // Instantiate loser address for use later
        address loser;

        // Loop through all participants to find loser
        for (uint i = 0; i < duels[_duelID].participantCount; i++) {
            if (duels[_duelID].addresses[i] != winner) {
                // If loser, save their address
                loser = duels[_duelID].addresses[i];
            }
        }

        // If winner was the NFT staker, award them the balance and return their NFT
        if (IERC721(nishibNFT).ownerOf(tokenId) == winner) {
            // Adjust user staked token balances
            nishibBalances[loser] -= pot;
            nishibBalances[winner] += pot;
            
            // Return staked NFT
            IERC721(nishibNFT).safeTransferFrom(address(this), winner, tokenId);
            // Clear staking record
            duels[_duelID].nftPayout = 0;
        } else {
            // If the winner was the previous winner, transfer the loser's NFT to them
            IERC721(nishibNFT).safeTransferFrom(address(this), winner, tokenId);
            // Clear staking record
            duels[_duelID].nftPayout = 0;
        }
    }

    // Internal function to handle PVP and PVPPlus NFT transfers
    function _adjustNFTOwnership(uint256 _duelID) internal {
        // Retrieve winner
        address winner = duels[_duelID].winner;

        // Transfer all participant NFTs to winner
        for (uint i = 0; i < duels[_duelID].participantCount; i++) {
            // Confirm participant is not winner
            if (duels[_duelID].addresses[i] != winner) {
                // Retrieve participant's staked NFT tokenId
                uint256 tokenId = duels[_duelID].tokenIDs[i];

                _transferNFT(address(this), winner, tokenId);
            }
        }
    }

    // Internal function to process different game mode logic
    function _executeTransfers(uint256 _duelID) internal {
        // Retrireve duel game mode
        Mode gameMode = duels[_duelID].mode;

        // Execute logic specific to game mode
        if (gameMode == Mode.SimpleBet ||
            gameMode == Mode.Jackpot) { // SimpleBet and Jackpot
                _adjustBalances(_duelID);
        }
        else if (gameMode == Mode.DoubleOrNothing) { // DoubleOrNothing
            _adjustDONBalances(_duelID);
        }
        else if (gameMode == Mode.PVP) { // PVP
            _adjustNFTOwnership(_duelID);
        }
        else if (gameMode == Mode.PVPPlus) { // PVPPlus
            _adjustBalances(_duelID);
            _adjustNFTOwnership(_duelID);
        }
        else {
            revert InvalidMode({
                duelID: _duelID,
                mode: gameMode
            });
        }

        // If no revert, announce Duel execution
        emit DuelExecuted({
            executor: msg.sender,
            winner: duels[_duelID].winner,
            duelID: _duelID
        });
    }

    // Internal function to handle processing refunds in the event of a cancelation
    function _executeRefunds(uint256 _duelID) internal {
        // Retrireve duel game mode
        Mode gameMode = duels[_duelID].mode;

        // Execute logic specific to game mode
        if (gameMode == Mode.SimpleBet ||
            gameMode == Mode.DoubleOrNothing ||
            gameMode == Mode.Jackpot) { // SimpleBet/DoubleOrNothing/Jackpot
                _refundTokens(_duelID);
        }
        else if (gameMode == Mode.PVP) { // PVP
            _refundNFTs(_duelID);
        }
        else if (gameMode == Mode.PVPPlus) { // PVPPlus
            _refundTokens(_duelID);
            _refundNFTs(_duelID);
        }
    }

    /*//////////////////////////////////////////////////////////////
                GAME MODE LOGIC
    //////////////////////////////////////////////////////////////*/

    // Internal sorting logic to determine winner
    function _determineWinner(uint256 _duelID) internal view returns (address winner) {
        // Store winning index value and vrfOutput for loop iterations
        uint256 winningIndex;

        // Loop through all vrfOutputs to find highest vrfOutput (Linear Sort)
        for (uint i = 0; i < duels[_duelID].participantCount; i++) {
            // Retrieve vrfOutput for index i Duel participant
            // In the event of a collision, lowest index wins
            uint256 ivrfOutput = duels[_duelID].vrfOutput[i];
            if (ivrfOutput > duels[_duelID].vrfOutput[winningIndex]) {
                winningIndex = i;
            }
        }

        // Determine winning address
        winner = duels[_duelID].addresses[winningIndex];

        return winner;
    }

    // Internal function logic for enabling the DoubleOrNothing Mode
    function _enableDON(uint256 _duelID) internal returns (bool) {
        // If both parties have enabled DONSwitch, enable DON mode
        if (duels[_duelID].DONSwitch[duels[_duelID].addresses[0]] == true &&
            duels[_duelID].DONSwitch[duels[_duelID].addresses[1]] == true) {
                // Enable DoubleOrNothing Mode
                duels[_duelID].mode = Mode.DoubleOrNothing;

                emit DuelDONEnabled(_duelID);

                // Generate vrfDONSalt
                _vrfGenerateDONSalt(_duelID);

                return true;
            }
        else {
            return false;
        }
    }

    // Internal DoubleOrNothing mode logic
    function _doubleOrNothing(uint256 _duelID) internal {
        // Check if DON can be enabled (true if both have flipped DONSwitch)
        bool enabled = _enableDON(_duelID);

        if (enabled) {
            // Rerun full duel execution with DON Mode enabled
            // New VRF values will be generated during salting process
            _executeDuel(_duelID);
        }
    }

    /*//////////////////////////////////////////////////////////////
                DUEL-SPECIFIC INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // Internal duel initialization logic
    // Cannot be used to initialize Jackpot duels
    function _initializeDuel(
        address _initializer,
        uint256 _tokenId,
        uint256 _bet,
        Mode _mode
    ) internal returns (uint256 _duelID) {
        // Block DoubleOrNothing as it more of a modifier than a mode
        if (_mode == Mode.DoubleOrNothing) {
            revert InvalidMode({
                duelID: Counters.current(duelCount),
                mode: _mode
            });
        }

        // Prevent more than one active jackpot
        if (_mode == Mode.Jackpot && 
            duels[jackpotIndex].deadline < block.timestamp) {
                revert ImproperJackpotInitialization({ jackpotIndex: jackpotIndex });
        }

        // Prevent non-PVP bets below minimum and above maximum
        if (_bet < minimumBet) {
            revert BetBelowThreshold({
                bet: _bet,
                threshold: minimumBet
            });
        } else if (_bet > maximumBet) {
            revert BetAboveThreshold({
                bet: _bet,
                threshold: maximumBet
            });
        // Transfer NFT if (_bet is zero and PVP mode) is selected or if PVPPlus is selected
        } else if ((_bet == 0 && _mode == Mode.PVP) || 
            _mode == Mode.PVPPlus) {
                _transferNFT(_initializer, address(this), _tokenId);
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
        // If Jackpot, overwrite deadline
        if (_mode == Mode.Jackpot) {
            duels[_duelID].deadline = block.timestamp + jackpotExpiry;
        }
        duels[_duelID].participantCount += 1;
        duels[_duelID].tokenPayout += _bet;

        // Store contract balance for balance checks
        uint256 balance = IERC20(nishibToken).balanceOf(address(this));
        // Transfer initializer's bet to contract
        bool success = _transferToken(_initializer, address(this), _bet);
        // Throw error if deposit not successful
        if (!success) {
            revert TransferFailed({
                sender: _initializer,
                recipient: address(this),
                amount: _bet
            });
        }
        // Throw error if contract balance didn't increase and bet is > 0
        if (_bet > 0) {
            require(IERC20(nishibToken).balanceOf(address(this)) > balance, "BALANCE_DIDNT_INCREASE");
        }

        // Generate initial VRF hash
        duels[_duelID].vrfInput.push(_vrfGenerateInput(_initializer, _duelID));

        // Increment duelCount
        Counters.increment(duelCount);

        emit DuelInitiated(_initializer, _duelID);

        return _duelID;
    }

    // Internal duel cancelation logic
    function _cancelDuel(uint256 _duelID) internal {
        // Call asset refund logic
        _executeRefunds(_duelID);

        // Alter duel struct to reflect cancelation
        duels[_duelID].status = Status.Canceled;

        emit DuelCanceled(msg.sender, _duelID);
    }

    // Populate Duel storage
    function _addToDuel(uint256 _tokenId, uint256 _duelID) internal {
        duels[_duelID].addresses.push(msg.sender);
        duels[_duelID].tokenIDs.push(_tokenId);
        duels[_duelID].vrfInput.push(_vrfGenerateInput(msg.sender, _duelID));
        duels[_duelID].participantCount += 1;
    }

    // Internal duel join logic
    // TODO: Needs to engage all Duel fields, reference _initializeDuel()
    function _joinDuel(uint256 _tokenId, uint256 _duelID) internal {
        // Retrieve duel mode and bet for code clarity
        Mode mode = duels[_duelID].mode;
        uint256 bet = duels[_duelID].bet;

        // Block joining DoubleOrNothing mode as it more of a modifier than a mode
        // DoubleOrNothing rolls are handled by doubleOrNothingDuel()
        if (mode == Mode.DoubleOrNothing) {
            revert InvalidMode({
                duelID: _duelID,
                mode: mode
            });
        }
        // SimpleBet and Jackpot execution logic
        else if (mode == Mode.SimpleBet || mode == Mode.Jackpot) {
            // Handle token transfer and related Duel data
            _transferToken(msg.sender, address(this), bet);
            duels[_duelID].tokenPayout += bet;

            // Execute remaining duel logic
            _addToDuel(_tokenId, _duelID);
        }
        // PVP execution logic
        else if (mode == Mode.PVP) {
            // Handle NFT transfer
            _transferNFT(msg.sender, address(this), _tokenId);

            // Execute remaining duel logic
            _addToDuel(_tokenId, _duelID);
        }
        // PVPPlus execution logic
        else if (mode == Mode.PVPPlus) {
            // Handle token transfer and related Duel data
            _transferToken(msg.sender, address(this), bet);
            duels[_duelID].tokenPayout += bet;

            // Handle NFT transfer
            _transferNFT(msg.sender, address(this), _tokenId);

            // Execute remaining duel logic
            _addToDuel(_tokenId, _duelID);
        }
        // Throw if an invalid Mode was somehow passed
        else {
            revert InvalidMode({
                duelID: _duelID,
                mode: mode
            });
        }
    }

    // Internal duel execution logic
    function _executeDuel(uint256 _duelID) internal returns (address winner) {
        // Don't regenerate vrfSalt if vrfDONSalt is present
        if (duels[_duelID].vrfDONSalt == bytes32(0)) {
            // Generate vrfSalt
            duels[_duelID].vrfSalt = _vrfGenerateSalt(_duelID);
        }

        // Now that vrfSalt or vrfDONSalt is generated, generate everyone's vrfOutputs
        _vrfGenerateOutputs(_duelID);

        // Determine winner
        winner = _determineWinner(_duelID);

        // Set winning address in Duel data
        duels[_duelID].winner = winner;

        // Process specific game mode logic
        _executeTransfers(_duelID);

        // Set Duel Status to Completed
        duels[_duelID].status = Status.Completed;

        return winner;
    }

    function _withdrawDuel(uint256 _duelID, address _recipient) internal returns (bool success) {
        // Retrieve pot
        uint256 pot = duels[_duelID].tokenPayout;

        // Validate that _recipient is entitled to pot
        if (nishibBalances[_recipient] < pot) {
            revert InsufficientBalance({
                sender: address(this),
                recipient: _recipient,
                required: pot,
                balance: nishibBalances[_recipient]
            });
        }

        // Process withdrawal logic
        success = _transferToken(address(this), _recipient, pot);

        // Update Duel Status
        duels[_duelID].status = Status.PotPaid;

        emit DuelPotWithdrawn(_recipient, _duelID, pot);

        // Increment total payout via pot
        Counters.increment(totalPayout);

        // Adjust Duel tokenPayout to avoid double withdraws
        duels[_duelID].tokenPayout -= pot;

        return success;
    }

    /*//////////////////////////////////////////////////////////////
                PUBLIC DUEL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // Public function to initiate a duel instance
    // Double or nothing is the only mode that cannot be initiated
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
    function cancelDuel(uint256 _duelID) public {
        // Confirm Duel Status is valid for cancelation
        if (duels[_duelID].status != Status.Initialized ||
            (duels[_duelID].status == Status.Completed &&
                duels[_duelID].mode == Mode.DoubleOrNothing)) {
            revert InvalidStatus({
                duelID: _duelID,
                current: duels[_duelID].status
            });
        } else if (duels[_duelID].mode == Mode.Jackpot) {
            revert ImproperJackpotCancelation({ duelID: _duelID });
        }

        // Confirm participantCount is > 0 to prevent underflow
        if (duels[_duelID].participantCount < 1) {
            revert NoParticipants({ duelID: _duelID });
        }

        // Confirm tokenPayout is enough to cover all participants
        if (duels[_duelID].tokenPayout < (duels[_duelID].participantCount * duels[_duelID].bet)) {
            revert InsufficientBalance({
                sender: address(this),
                recipient: address(0xE),
                required: duels[_duelID].participantCount * duels[_duelID].bet,
                balance: duels[_duelID].tokenPayout
            });
        }

        // Confirm contract has tokenPayout balance
        if (IERC20(nishibToken).balanceOf(address(this)) < duels[_duelID].tokenPayout) {
            revert InsufficientBalance({
                sender: address(this),
                recipient: address(0xF),
                required: duels[_duelID].tokenPayout,
                balance: IERC20(nishibToken).balanceOf(address(this))
            });
        }

        // Prevent cancelation of duel if expiry deadline is not reached
        // Expiry is enforced to prevent MEV attacks
        _confirmDeadline(_duelID);

        // Confirm sender is duel initiator
        _confirmInitiator(_duelID);

        // Run internal duel cancellation logic
        _cancelDuel(_duelID);
    }

    // Public function to allow anyone to join a duel once per wallet
    function joinDuel(uint256 _tokenId, uint256 _duelID) public {
        // Confirm token and NFT approvals and ownership
        _confirmToken(msg.sender, duels[_duelID].bet);
        _confirmNFT(msg.sender, _tokenId);

        // Prevent joining a completed duel
        if (duels[_duelID].status == Status.Completed) {
            revert InvalidStatus({
                duelID: _duelID,
                current: duels[_duelID].status
            });
        }

        // Block joining DoubleOrNothing mode as it more of a modifier than a mode
        // DoubleOrNothing rolls are handled by doubleOrNothingDuel()
        if (duels[_duelID].mode == Mode.DoubleOrNothing) {
            revert InvalidMode({
                duelID: _duelID,
                mode: duels[_duelID].mode
            });
        }

        // Require prior initialization by checking participants
        if (duels[_duelID].participantCount > 0) {
            revert NotEnoughParticipants({ duelID: _duelID });
        }

        // Prevent double joins
        if (_confirmParticipant(msg.sender, _duelID) >= 0) {
            revert AlreadyJoined({ duelID: _duelID });
        }

        // Call internal duel join logic
        _joinDuel(_tokenId, _duelID);
    }

    // Public function allowing any participant to execute game logic and engage VRF logic
    function executeDuel(uint256 _duelID) public returns (address winner) {
        // Confirm Duel Status is not Completed
        if (duels[_duelID].status == Status.Completed) {
            revert InvalidStatus({
                duelID: _duelID,
                current: duels[_duelID].status
            });
        }

        // Require at least two participants as that is minimum edge case
        if (duels[_duelID].participantCount > 1) {
            revert NotEnoughParticipants({ duelID: _duelID });
        }

        // Restrict duel execution to participants to prevent MEV abuse
        _confirmParticipant(msg.sender, _duelID);

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

        // Run internal duel execution logic
        winner = _executeDuel(_duelID);

        return winner;
    }

    // Allow loser to stake ANY owned NitroShiba NFT as their DoubleOrNothing NFT wager
    // Both winner and loser needs to call to engage. Second caller triggers execution.
    // Designed to allow multiple runs of DoubleOrNothing
    // Only SimpleBet with two participants can run DoubleOrNothing
    function doubleOrNothingDuel(uint256 _duelID, uint256 _tokenId) public {
        // Require SimpleBet Mode
        if (duels[_duelID].mode != Mode.SimpleBet) {
            revert InvalidMode({
                duelID: _duelID,
                mode: duels[_duelID].mode
            });
        }

        // Confirm winner hasn't withdrawn pot
        if (duels[_duelID].status == Status.PotPaid) {
            revert InvalidStatus({
                duelID: _duelID,
                current: duels[_duelID].status
            });
        }

        // Require only two participants
        if (duels[_duelID].participantCount > 2) {
            revert TooManyParticipants({
                duelID: _duelID,
                required: 2,
                count: duels[_duelID].participantCount
            });
        }

        // If Allow only winner and loser to run logic
        // If not winner, then loser only
        if (_confirmWinner(_duelID) == msg.sender) {
            // Set DoubleOrNothing switch to true
            duels[_duelID].DONSwitch[msg.sender] = true;
        } else {
            // Non losers will experience an error here
            _confirmLoser(_duelID);

            // Confirm NFT ownership and approval are still good
            _confirmNFT(msg.sender, _tokenId);

            // Process NFT transfer
            _transferNFT(msg.sender, address(this), _tokenId);

            // Set DON NFT stake
            duels[_duelID].nftPayout = _tokenId;

            // Set DoubleOrNothing switch to true
            duels[_duelID].DONSwitch[msg.sender] = true;
        }

        emit DuelDONSwitched(msg.sender, _duelID);

        // Call remaining DoubleOrNothing logic
        _doubleOrNothing(_duelID);
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