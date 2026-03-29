# Foundry Smart Contract Lottery

## Overview

This project implements a provably fair, decentralized raffle (lottery) on Ethereum using Solidity. The core contract `Raffle.sol` leverages two Chainlink services to guarantee fairness and automation:

- **Chainlink VRF v2.5** — cryptographically verifiable randomness for winner selection
- **Chainlink Automation** — trustless, time-based triggering to pick the winner automatically

Players enter the raffle by sending ETH. After a set time interval passes, Chainlink Automation triggers the draw, Chainlink VRF returns a random number, and the entire prize pool is sent to the winner in one transaction.

---

## Contract: `Raffle.sol`

### State Machine

The contract operates in one of two states:

| State | Description |
|---|---|
| `OPEN` | The raffle is accepting new entries |
| `CALCULATING` | A VRF request is in-flight; no new entries allowed |

### Constructor Parameters

| Parameter | Type | Description |
|---|---|---|
| `subscriptionId` | `uint256` | Chainlink VRF subscription ID funding the randomness requests |
| `gasLane` | `bytes32` | VRF key hash — caps the gas price paid per request |
| `interval` | `uint256` | Seconds between each raffle round |
| `entranceFee` | `uint256` | Minimum ETH (in wei) required to enter |
| `callbackGasLimit` | `uint32` | Max gas for the VRF callback function |
| `vrfCoordinatorV2` | `address` | Address of the Chainlink VRF Coordinator contract |

### Key Functions

#### `enterRaffle()`
- Players call this with `msg.value >= entranceFee`
- Reverts with `Raffle__SendMoreToEnterRaffle` if underpaid
- Reverts with `Raffle__RaffleNotOpen` if the raffle is in `CALCULATING` state
- Emits `RaffleEnter(address player)`

#### `checkUpkeep(bytes)`
- Called by Chainlink Automation nodes off-chain to decide if work is needed
- Returns `upkeepNeeded = true` only when **all four** conditions hold:
  1. Raffle is `OPEN`
  2. Time interval has elapsed since last round
  3. At least one player is entered
  4. Contract holds a non-zero ETH balance

#### `performUpkeep(bytes)`
- Called by Chainlink Automation when `checkUpkeep` returns `true`
- Transitions state to `CALCULATING`
- Fires a VRF random words request to the Chainlink coordinator
- Emits `RequestedRaffleWinner(uint256 requestId)`

#### `fulfillRandomWords(uint256, uint256[])`
- Internal callback invoked by the VRF coordinator with the verified random number
- Selects winner: `randomWords[0] % players.length`
- Transfers the entire contract balance to the winner
- Resets the players array, resets timestamp, returns state to `OPEN`
- Emits `WinnerPicked(address player)`
- Reverts with `Raffle__TransferFailed` if the ETH transfer fails

### Custom Errors

| Error | When thrown |
|---|---|
| `Raffle__SendMoreToEnterRaffle` | Entrance fee not met |
| `Raffle__RaffleNotOpen` | Entry attempted while `CALCULATING` |
| `Raffle__UpkeepNotNeeded(balance, numPlayers, state)` | `performUpkeep` called when conditions not met |
| `Raffle__TransferFailed` | ETH transfer to winner fails |

### Events

| Event | Emitted when |
|---|---|
| `RaffleEnter(address player)` | A player successfully enters |
| `RequestedRaffleWinner(uint256 requestId)` | VRF request is dispatched |
| `WinnerPicked(address player)` | Winner receives the prize |

---

## Project Structure

```
src/
  Raffle.sol                  # Core raffle contract
script/
  DeployRaffle.s.sol          # Deployment script
  HelperConfig.s.sol          # Per-chain config + local mock setup
  Interactions.s.sol          # CreateSubscription, FundSubscription, AddConsumer
test/
  unit/
    RaffleTest.t.sol          # Full unit test suite (14 tests)
  staging/
    RaffleStagingTest.t.sol   # Staging tests (skipped on local chain)
  mocks/
    LinkToken.sol             # ERC677 LINK token mock for local testing
lib/
  chainlink-brownie-contracts/ # Chainlink VRF + Automation contracts
  forge-std/                   # Foundry test utilities
  foundry-devops/              # DevOps helpers
  solmate/                     # ERC20 base used by LinkToken mock
```

---

## Test Suite

Tests are run with `forge test`. All 16 tests pass.

```
Ran 14 tests for test/unit/RaffleTest.t.sol
Ran  2 tests for test/staging/RaffleStagingTest.t.sol
Total: 16 passed, 0 failed
```

### Unit Tests — `test/unit/RaffleTest.t.sol`

The unit tests run entirely on a local Anvil chain using mocks (`VRFCoordinatorV2_5Mock`, `LinkToken`). `DeployRaffle` is called in `setUp` so every test starts with a freshly deployed, fully configured raffle.

#### Raffle State

| Test | What it verifies |
|---|---|
| `testRaffleInitializesInOpenState` | Raffle state is `OPEN` immediately after deployment |

#### Entering the Raffle

| Test | What it verifies |
|---|---|
| `testRaffleRevertsWHenYouDontPayEnough` | Calling `enterRaffle()` with zero ETH reverts with `Raffle__SendMoreToEnterRaffle` |
| `testRaffleRecordsPlayerWhenTheyEnter` | Player address is stored in the players array after a valid entry |
| `testEmitsEventOnEntrance` | `RaffleEnter` event is emitted with the correct player address |
| `testDontAllowPlayersToEnterWhileRaffleIsCalculating` | Entering after `performUpkeep` has been called reverts with `Raffle__RaffleNotOpen` |

#### `checkUpkeep`

| Test | What it verifies |
|---|---|
| `testCheckUpkeepReturnsFalseIfItHasNoBalance` | Returns `false` when no ETH in contract (no players) |
| `testCheckUpkeepReturnsFalseIfRaffleIsntOpen` | Returns `false` when state is `CALCULATING` |
| `testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed` | Returns `false` when interval has not elapsed, even with a player entered |
| `testCheckUpkeepReturnsTrueWhenParametersGood` | Returns `true` when all conditions are met (player entered + time elapsed) |

#### `performUpkeep`

| Test | What it verifies |
|---|---|
| `testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue` | Succeeds without revert when upkeep conditions are met |
| `testPerformUpkeepRevertsIfCheckUpkeepIsFalse` | Reverts with `Raffle__UpkeepNotNeeded` when conditions are not met |
| `testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId` | State transitions to `CALCULATING` and a non-zero `requestId` is emitted in logs |

#### `fulfillRandomWords`

| Test | What it verifies |
|---|---|
| `testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep` | VRF mock reverts `InvalidRequest` for request IDs that were never issued |
| `testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney` | With 4 players, a winner is correctly selected, receives the full prize pool, players array is reset, timestamp is updated, and state returns to `OPEN` |

---

### Staging Tests — `test/staging/RaffleStagingTest.t.sol`

These tests are intended for use against a live testnet fork. They use the `onlyOnDeployedContracts` modifier which **skips execution on a local chain** (chainId `31337`), so they pass trivially in a local `forge test` run without doing any work.

| Test | What it verifies (on a live fork) |
|---|---|
| `testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep` | VRF requests that were never made cannot be fulfilled |
| `testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney` | Full end-to-end draw: players enter, upkeep fires, VRF fulfills, winner paid |

---

## Local Network Setup

When running on a local Anvil chain, `HelperConfig` automatically:

1. Deploys `VRFCoordinatorV2_5Mock` and creates a VRF subscription
2. Deploys `LinkToken` (ERC677 mock)
3. `DeployRaffle` registers the deployed `Raffle` as an authorized VRF consumer via `AddConsumer`
4. `setUp` in the unit tests mints LINK to the subscription owner and funds the subscription so VRF callbacks succeed

No manual configuration is needed to run the tests locally.

---

## Running Tests

```bash
# Run all tests
forge test

# Run with verbose output
forge test -v

# Run only unit tests
forge test --match-path test/unit/RaffleTest.t.sol

# Run a specific test with full trace
forge test --match-test testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney -vvvv
```
