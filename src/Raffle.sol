// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

/*

These are import statements. 
We have imported the following contracts and libraries from the Chainlink repository:
1. VRFConsumerBaseV2Plus: This is a base contract that provides functionality for
consuming Chainlink VRF (Verifiable Random Function) Version 2. It allows us to request random numbers and handle the response.
2. VRFV2PlusClient: This is a library that provides helper functions for interacting with the Chainlink VRF Version 2. It includes functions for creating random words requests and handling the response.
3. AutomationCompatibleInterface: This is an interface that defines the functions required for a contract to be compatible with Chainlink Automation (formerly known as Chainlink Keepers). It includes the checkUpkeep and performUpkeep functions that are called by the Chainlink Automation nodes to determine when to

*/

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

/**
 * @title A sample Raffle Contract
 * @author Patrick Collins
 * @notice This contract is for creating a sample raffle contract
 * @dev This implements the Chainlink VRF Version 2
 */

contract Raffle is VRFConsumerBaseV2Plus, AutomationCompatibleInterface {
    /*
    
    These Errors are custom errors that we can use in our contract to provide more specific error messages when certain conditions are not met.
    1. Raffle__UpkeepNotNeeded: This error is thrown when the performUpkeep function is called but the conditions for performing upkeep are not met. It includes parameters for the current balance of the contract, the number of players, and the current state of the raffle.
    2. Raffle__TransferFailed: This error is thrown when the transfer of funds to the winner fails. It does not include any parameters.
    3. Raffle__SendMoreToEnterRaffle: This error is thrown when a player tries to enter the raffle but does not send enough ETH to cover the entrance fee. It does not include any parameters.
    4. Raffle__RaffleNotOpen: This error is thrown when a player tries to enter the raffle but the raffle is not currently open. It does not include any parameters.    

    */

    /* Errors */
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState
    );
    error Raffle__TransferFailed();
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__RaffleNotOpen();

    /* Type declarations */

    /*
    This is an enum that defines the possible states of the raffle. It has two states:
    1. OPEN: This state indicates that the raffle is currently open and accepting entries from players.
    2. CALCULATING: This state indicates that the raffle is currently calculating the winner and is not accepting new entries from players. This state is typically set when the performUpkeep function is called and the conditions for performing upkeep are met. Once the winner is calculated and the funds are transferred, the state is set back to OPEN to allow for the next round of the raffle.
     */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    /*
        State Variables
        The following are state variables that we will use in our contract to store important information about the raffle and the Chainlink VRF configuration. These variables are declared as private and immutable, meaning they can only be set once during contract deployment and cannot be changed afterwards.
        1. i_subscriptionId: This variable stores the subscription ID for the Chainlink VRF service. It is used to identify the subscription that will be used to pay for VRF requests 
        2. i_gasLane: This variable stores the gas lane (key hash) for the Chainlink VRF service. It is used to specify the maximum gas price that can be paid for VRF requests.
        3. i_callbackGasLimit: This variable stores the callback gas limit for the Chainlink VRF service. It is used to specify the maximum amount of gas that can be used for the callback function that handles the VRF response.
        4. REQUEST_CONFIRMATIONS: This constant variable specifies the number of confirmations that the Chainlink VRF service should wait for before fulfilling a VRF request. It is set to 3, which means that the VRF response will only be fulfilled after 3 confirmations have been received on the blockchain.
        5. NUM_WORDS: This constant variable specifies the number of random words that should be requested from the Chainlink VRF service. It is set to 1, which means that only one random word will be requested for each VRF request. 

        Lottery Variables
        The following are state variables that we will use to manage the state of the raffle and store information about the players and the winner. These variables are also declared as private and immutable, meaning they can only be set once during contract deployment and cannot be changed afterwards.
        1. i_interval: This variable stores the time interval (in seconds) between raffle runs. It is used to determine when the next round of the raffle should start.
        2. i_entranceFee: This variable stores the entrance fee (in wei) that players must pay to enter the raffle. It is used to ensure that players send enough ETH when they call the enterRaffle function. 
        3. s_lastTimeStamp: This variable stores the timestamp of the last time the raffle was run. It is used to determine when the next round of the raffle should start based on the specified interval.
        4. s_recentWinner: This variable stores the address of the most recent winner of the raffle. It is updated each time a new winner is picked and can be accessed using the getRecentWinner function.
        5. s_players: This variable is an array that stores the addresses of the players who have entered the raffle. It is updated each time a player calls the enterRaffle function and can be accessed using the getPlayer function.
        6. s_raffleState: This variable stores the current state of the raffle (OPEN or CALCULATING). It is updated each time the performUpkeep function is called and can be accessed using the getRaffleState function.  
     */

    /* State variables */
    // Chainlink VRF Variables
    uint256 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    // Lottery Variables
    uint256 private immutable i_interval;
    uint256 private immutable i_entranceFee;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    address payable[] private s_players;
    RaffleState private s_raffleState;

    /*

    The following Events are used to emit important information about the state of the raffle and the actions taken by players. These events can be listened to by external applications (such as a frontend interface) to provide real-time updates about the raffle.
    1. RequestedRaffleWinner: This event is emitted when a request for a random winner is made to the Chainlink VRF service. It includes the requestId parameter, which is the unique identifier for the VRF request. This event can be used to track when a new winner is being calculated.
    2. RaffleEnter: This event is emitted when a player successfully enters the raffle by calling the enterRaffle function. It includes the player parameter, which is the address of the player who entered the raffle. This event can be used to track the number of players and who is participating in the raffle.
    3. WinnerPicked: This event is emitted when a winner is successfully picked and the funds are transferred to the winner. It includes the player parameter, which is the address of the player who won the raffle. This event can be used to track the winners of the raffle and provide updates to participants and observers.
     */

    /* Events */
    event RequestedRaffleWinner(uint256 indexed requestId);
    event RaffleEnter(address indexed player);
    event WinnerPicked(address indexed player);

    /*
    The constructor function takes several parameters that are used to intialize the state variables of the contract. These parameters include:
    1. subscriptionId: The subscription ID for the Chainlink VRF service, which is used to identify the subscription that will be used to pay for VRF requests.
    2. gasLane: The gas lane (key hash) for the Chainlink VRF service, which is used to specify the maximum gas price that can be paid for VRF requests.
    3. interval: The time interval (in seconds) between raffle runs, which is used to determine when the next round of the raffle should start.
    4. entranceFee: The entrance fee (in wei) that players must pay to enter the raffle, which is used to ensure that players send enough ETH when they call the enterRaffle function.
    5. callbackGasLimit: The callback gas limit for the Chainlink VRF service, which is used to specify the maximum amount of gas that can be used for the callback function that handles the VRF response.
    6. vrfCoordinatorV2: The address of the Chainlink VRF Coordinator contract, which is used to initialize the VRFConsumerBaseV2Plus contract and enable the contract to make VRF requests and receive responses. 

    */

    /* Functions */
    constructor(
        uint256 subscriptionId,
        bytes32 gasLane, // keyHash
        uint256 interval,
        uint256 entranceFee,
        uint32 callbackGasLimit,
        address vrfCoordinatorV2
    ) VRFConsumerBaseV2Plus(vrfCoordinatorV2) {
        i_gasLane = gasLane;
        i_interval = interval;
        i_subscriptionId = subscriptionId;
        i_entranceFee = entranceFee;
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
        i_callbackGasLimit = callbackGasLimit;
        // uint256 balance = address(this).balance;
        // if (balance > 0) {
        //     payable(msg.sender).transfer(balance);
        // }
    }

    /*
    The enterRaffle function is a public payable function that allows players to enter the raffle by sending ETH to the contract. There is a if statement that checks if the amount of ETH to msg.value is greater than or equal to the entrance fee i_entranceFee. If the amount of ETH sent is less than the entrance fee, the function will revert with the Raffle__SendMoreToEnterRaffle error. 

    The function then checks if the s_raffleState is OPEN. If the raffle is not open, the function will revert with the Raffle__RaffleNotOpen error.

    And then s_players.push(payable(msg.sender)) is used to add the address of the player who called the function to the s_players array. The address is cast to a payable address to allow for future transfers of funds to the player if they win the raffle.

    Finally, the function emits a RaffleEnter event with the address of the player who entered the raffle. This event can be used to track the number of players and who is participating in the raffle.

    */

    function enterRaffle() public payable {
        // require(msg.value >= i_entranceFee, "Not enough value sent");
        // require(s_raffleState == RaffleState.OPEN, "Raffle is not open");
        if (msg.value < i_entranceFee) {
            revert Raffle__SendMoreToEnterRaffle();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        // Emit an event when we update a dynamic array or mapping
        // Named events with the function name reversed
        emit RaffleEnter(msg.sender);
    }

    /**
     * @dev This is the function that the Chainlink Keeper nodes call
     * they look for `upkeepNeeded` to return True.
     * the following should be true for this to return true:
     * 1. The time interval has passed between raffle runs.
     * 2. The lottery is open.
     * 3. The contract has ETH.
     * 4. Implicity, your subscription is funded with LINK.
     */

    /*
    
    The checkUpkeep function is a public view function that overrides and then returns a boolean value indicating whether upkeep is needed for the raffle. 

    Lets break down the conditions of this function:
    1. the checkUpkeep takes a bytes memory parameter called checkData, which is not used in this implementation but can be used to pass additional data if needed.
    2. the function returns a boolean value called upkeepNeeded, which indicates whether the conditions for performing upkeep are met. It also returns a bytes memory value called performData, which is not used in this implementation but can be used to pass additional data if needed.
    3. the function checks several conditions to determine if upkeep is needed:
    - isOpen: This condition checks if the raffle is currently open by comparing the s_raffleState variable to the OPEN state of the RaffleState enum.
    - timePassed: This condition checks if the specified time interval has passed since the last time the raffle was run by comparing the current block timestamp to the s_lastTimeStamp variable and the i_interval variable.
    - hasPlayers: This condition checks if there are any players currently entered in the raffle by checking the length of the s_players array.
    - hasBalance: This condition checks if the contract has any ETH balance by checking the balance of the contract using address(this).balance.
    4. If all of these conditions are true, then upkeepNeeded is set to true, indicating that the performUpkeep function should be called to perform the upkeep tasks (such as requesting a random winner from the Chainlink VRF service). If any of these conditions are false, then upkeepNeeded is set to false, indicating that the performUpkeep function should not be called at this time.   

    */
    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool hasPlayers = s_players.length > 0;
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (timePassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0"); // can we comment this out?
    }

    /**
     * @dev Once `checkUpkeep` is returning `true`, this function is called
     * and it kicks off a Chainlink VRF call to get a random winner.
     */

    /*

    The performUpkeep function takes a bytes calldata parameter called performData, which is not used in this implementation but can be used to pass additional data if needed. It is an external function that overrides and takes a boolean value called upkeepNeeded from the checkUpkeep function. 

    The function first checks if upkeepNeeded is true. If it is not true, the function reverts with the Raffle__UpkeepNotNeeded error, address(this).balance, s_players.length, and uint256(s_raffleState) are passed as parameters to provide information about the current state of the raffle when the error is thrown. This is useful for debugging and understanding why the upkeep was not needed at the time the function was called.

    if upkeepNeeded is true, the function proceeds to set the s_raffleState to CALCULATING to indicate that the raffle is currently calculating the winner and is not accepting new entries from players.



    */

    function performUpkeep(bytes calldata /* performData */) external override {
        (bool upkeepNeeded, ) = checkUpkeep("");
        // require(upkeepNeeded, "Upkeep not needed");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        s_raffleState = RaffleState.CALCULATING;

        // Will revert if subscription is not set and funded.
        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_gasLane,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );
        // Quiz... is this redundant?
        emit RequestedRaffleWinner(requestId);
    }

    /**
     * @dev This is the function that Chainlink VRF node
     * calls to send the money to the random winner.
     */
    function fulfillRandomWords(
        uint256,
        /* requestId */ uint256[] calldata randomWords
    ) internal override {
        // s_players size 10
        // randomNumber 202
        // 202 % 10 ? what's doesn't divide evenly into 202?
        // 20 * 10 = 200
        // 2
        // 202 % 10 = 2
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_players = new address payable[](0);
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(recentWinner);
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        // require(success, "Transfer failed");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /**
     * Getter Functions
     */
    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getNumWords() public pure returns (uint256) {
        return NUM_WORDS;
    }

    function getRequestConfirmations() public pure returns (uint256) {
        return REQUEST_CONFIRMATIONS;
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    function getPlayer(uint256 index) public view returns (address) {
        return s_players[index];
    }

    function getLastTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getInterval() public view returns (uint256) {
        return i_interval;
    }

    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }

    function getNumberOfPlayers() public view returns (uint256) {
        return s_players.length;
    }
}
