
# NitroShibaDuel

A simple on-chain game for holders of any Nitro Shiba NFT collection.




## Features

- Bet $NISHIB and/or your NFT
- Participate in community Jackpot rounds
- Win or lose it all in Double Or Nothing mode
- Rounds are not limited to two players
- MEV-resistant randomness
- No administrative withdraw function so contract is rug-proof
- Code is heavily commented to help anyone independently review it

## Modes

- 1\) SimpleBet
    - Each NFT holder places matching bets and the winner takes the pot
    - This is the only mode that can convert to DoubleOrNothing mode
- 2\) DoubleOrNothing
    - A two-player SimpleBet Duel can be converted into DoubleOrNothing
    - Must be toggled by both players before the SimpleBet winner withdraws
    - If SimpleBet has more than two players, DoubleOrNothing cannot be enabled
- 3\) PVP
    - Each NFT holder bets one of their NFTs against each other
    - Winner takes all
- 4\) PVPPlus
    - PVP but with a token bet as well
    - Basically SimpleBet + PVP
- 5\) Jackpot
    - Any NFT holder can trigger a jackpot round that lasts as long as the jackpotExpiry value
    - Only one jackpot can be running at any given time
    - Jackpot initiator can set the jackpot bet as long as it is within bet minimum and maximum thresholds

## FAQ

#### What administrative functions are present?

The admin can perform the following actions:

```solidity
    function changeMinimumBet_(uint256 _minimumBet) public onlyOwner {
        minimumBet = _minimumBet;
    }

    function changeMaximumBet_(uint256 _maximumBet) public onlyOwner {
        maximumBet = _maximumBet;
    }
    
    function changeDuelExpiry_(uint256 _duelExpiry) public onlyOwner {
        duelExpiry = _duelExpiry;
    }

    function changeJackpotExpiry_(uint256 _jackpotExpiry) public onlyOwner {
        jackpotExpiry = _jackpotExpiry;
    }

    function cancelJackpot_(uint256 _jackpotIndex) public onlyOwner {
        _cancelDuel(_jackpotIndex);
    }
```

#### What is the reasoning behind these administrative functions?

changeMinimumBet\_(uint256 \_minimumBet) \
changeMaximumBet_(uint256 _maximumBet)

    - These functions allow the contract owner to adjust the minimum and maximum bet thresholds
    - The primary purpose is that a minumum bet needs to be enforced to prevent transaction spam
    - The maximum bet prevents jackpot rounds from being initialized with too high a bet for all participants
        - Jackpots have an independent expiry and are only cancelable by admin
    - If the price of $NISHIB fluctuates wildly, limits will need to be adjusted

changeDuelExpiry_(uint256 \_duelExpiry) \
changeJackpotExpiry_(uint256 _jackpotExpiry)

    - These functions allow the contract owner to adjust duel and jackpot expiries
    - Duel expiry prevents MEV by not allowing bots to withdraw their bids before they can calculate vrfOutputs
    - Jackpot expiry is enforced by preventing anyone from executing it prematurely
    - The community may want these values adjusted over time, so the admin reserves the right to do so here

cancelJackpot_(uint256 _jackpotIndex)

    - Only the owner can cancel a Jackpot duel
    - Prevents jackpot initiators from trolling by canceling Jackpots
    - Contract owner is prevented from canceling if they participated in the jackpot

## Usage

```solidity
function initiateDuel(
    uint256 _tokenId,
    uint256 _bet,
    Mode _mode
) public returns (uint256 _duelID) { ... }
```

- 1\) Initiate Duel
    - This function is called to start a duel
    - Duel Mode is determined by _mode parameter
    - Returns the duelID for the interface

---

```solidity
function joinDuel(uint256 _tokenId, uint256 _duelID) public { ... }
```

- 2a\) Join Duel
    - This function processes all of the logic required to join an open duel, regardless of mode
    - All participants calling join must own NFT at _tokenId

---

```solidity
function cancelDuel(uint256 _duelID) public { ... }
```

- 2b\) Cancel Duel
    - Before a duel is executed, the initiator can cancel it
    - Cancelation processes asset (token and/or NFT) refunds for all participants (if any)
    - Must be run prior to duel execution

---

```solidity
function executeDuel(uint256 _duelID) public returns (address winner) { ... }
```

- 3\) Execute Duel
    - Allow only duel participants to execute duel
    - As long as enough duel participants have joined, execution can occur
    - Jackpot execution only occurs after the jackpot deadline
    - Returns winner address for the interface

---

```solidity
function doubleOrNothingDuel(uint256 _duelID, uint256 _tokenId) public { ... }
```

- 4\) Enable DoubleOrNothing Mode (optional)
    - Allows participants in a two-party SimpleBet to enable DoubleOrNothing mode
    - Only two participants is a hard requirement
    - Both parties must call this before executeDuel() can be called again

---

```solidity
function withdrawDuel(uint256 _duelID) public returns (bool success) { ... }
```

- 5\) Withdraw Duel Pot
    - Allows winner to withdraw duel pot
    - Once withdrawal has occurred, DoubleOrNothing mode cannot be enabled
    
## Installation

NitroShibaDuel was made with foundry, and thus can be installed as follows:

```bash
git clone https://github.com/Zodomo/NitroShibaDuel

cd NitroShibaDuel

forge install

forge build
```

## Authors

- Zodomo
    - [Twitter (@0xZodomo)](https://www.github.com/0xZodomo)
    - Ethereum (Zodomo.eth)

## Acknowledgements

 - NitroShiba
    - [Twitter (@NitroShiba)](https://twitter.com/NitroShiba)
    - [CoinGecko ($NISHIB)](https://www.coingecko.com/en/coins/nitroshiba)
    - [Telegram](http://t.me/NitroShibaPortal)
    - [Official Website](https://nitroshiba.xyz/)
    - [Discord](https://discord.gg/mfUZNXAS)