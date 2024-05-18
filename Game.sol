// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0 <0.9.0;

import "hardhat/console.sol";

contract Game {
    uint8 decksNr;
    uint8[] allCards;
    cardInfoStr[52] cardInfo;

    struct cardInfoStr {
        uint8 value;        // exp. 7
        string fullName;    // exp. "7♣"
    }

    struct playerState {
        uint256 bet;

        //  Hand ID (uint8) => Hand (uint8[] = card IDs 0-51)
        //  More than one hand ID, because the player can split multiple times
        mapping (uint8 => uint8[]) hands;
        //  The number of hands this player has
        uint8 handsNr;
        bool gotBlackjack;
    }

    //  Player's address => Player's state
    mapping (address => playerState) public allPlayerStates;

    address[] playersInGame;
    uint8 currentPlayerTurn;
    uint8 playersNr;

    address dealer;


    modifier onlyDealer() {
        require(dealer == msg.sender, "Only the dealer can take this action.");
        _;
    }
    modifier yourTurn(address you) {
        require(playersInGame[currentPlayerTurn] == you, "It is not your turn!");
        _;
    }


    constructor() {
        //  The dealer isn't a player, but the contract itself.
        //  (since the dealer doesn't make choices anyway)
        dealer = address(this);
        playersInGame.push(dealer);
        playersNr = 1;
    }

    function showPlayers() external view {
        for (uint8 i = 0; i < playersNr; i++) {
            if (playersInGame[i] == dealer)
                console.log(playersInGame[i], " (Dealer)");
            else
                console.log(playersInGame[i]);
        }
    }

    function joinGame() external {
        for (uint8 i = 0; i < playersNr; i++) {
            if (playersInGame[i] == msg.sender) {
                revert("You have already joined the game!");
            }
        }
        playersInGame.push(msg.sender);
        playersNr++;
    }

    //  TO-DO: Add modifier (contract's owner?)
    function startGame(uint8 _decksNr) public {
        require((_decksNr > 0 && _decksNr <= 8), "The number of decks must be between 1 and 8.");
        require(playersNr >= 2, "At least 2 players (including the dealer) are needed to play.");

        decksNr = _decksNr;
        initCardData();
        
        startRound();
        advanceTurn();
    }
    //  TO-DO: Add modifier (contract's owner?)
    function endGame() public {
        //  Reset players
        delete playersInGame;
        playersInGame.push(dealer);
        playersNr = 1;
    }

    function startRound() private {
        //  Put all cards back and shuffle them
        if (allCards.length <= 60)
            resetDecks();

        //  Each player draws two cards, but the dealer draws one.
        for (uint8 i = 0; i < playersNr; i++) {
            address p = playersInGame[i];
            
            allPlayerStates[p].handsNr = 1;
            allPlayerStates[p].gotBlackjack = false;

            if (p == dealer) {
                console.log(".");
                console.log("===%s (Dealer)===", p);
                allPlayerStates[p].hands[0].push(drawCard());
                getHandValue(p, 0);
            }
            else {
                console.log(".");
                console.log("===%s===", p);
                uint8 draw1 = drawCard();
                uint8 draw2 = drawCard();
                allPlayerStates[p].hands[0].push(draw1);
                allPlayerStates[p].hands[0].push(draw2);

                uint8 initialHandValue = getHandValue(p, 0);
                if (initialHandValue == 21) {
                    console.log("%s got a Blackjack!", p);
                    allPlayerStates[p].gotBlackjack = true;
                    //  Should be 3-to-2, but it's 2-to-1 because floating point
                    allPlayerStates[p].bet *= 2;
                }
            }
        }
    }
    function endRound() private {
        for (uint8 i = 0; i < playersNr; i++) {
            address p = playersInGame[i];

            if (allPlayerStates[p].bet > 0) {
                //  TO-DO: Pay player
                console.log("%s won %s", p, allPlayerStates[p].bet);
            }
            allPlayerStates[p].bet = 0;
            
            for (uint8 j = 0; j < allPlayerStates[p].handsNr; j++) {
                delete allPlayerStates[p].hands[j];
            }
        }
        console.log("Round ended!");
        console.log(".");
        console.log(".");
        console.log(".");
    }


    function initCardData() private {
        uint8[13] memory values = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 10, 10]; 
        string[13] memory valueNames = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"];
        string[4] memory suits = [unicode"♠", unicode"♥", unicode"♦", unicode"♣"];

        for (uint8 value = 0; value < 13; value++)
            for (uint8 suit = 0; suit < 4; suit++) {
                cardInfo[13 * suit + value].value = values[value];
                cardInfo[13 * suit + value].fullName = string.concat(valueNames[value], suits[suit]);
            }
    }

    //  TO-DO: Comment out, this is for debugging
    function mockHand(uint8 handId, uint8[] memory cardIds) public {
        for (uint i = 0; i < cardIds.length; i++) {
            allPlayerStates[msg.sender].hands[handId].push(cardIds[i]);
        }
    }
    //  TO-DO: Comment out, this is for debugging
    function mockDeck(uint8[] memory cardIds) public {
        delete allCards;
        for (uint i = 0; i < cardIds.length; i++) {
            allCards.push(cardIds[i]);
        }
    }

    //  Returns the value of cards in a player's hand
    //  exp: 2 + 3 + 7 => 12,   A + 4 => 15,   A + 6 + J => 17
    function getHandValue(address playerChecked, uint8 handId) public view returns (uint8) {
        uint8 handValue = 0;
        uint8 acesNr = 0;

        uint handSize = allPlayerStates[playerChecked].hands[handId].length;

        for (uint cardNr = 0; cardNr < handSize; cardNr++) {
            uint8 cardId = allPlayerStates[playerChecked].hands[handId][cardNr];
            handValue += cardInfo[cardId].value;
            
            //  Count the number of aces in the player's hand
            if (cardInfo[cardId].value == 1)
                acesNr += 1;

            console.log(getCardName(cardId));
        }

        //  Aces' value is either 1 or 11
        //  (whichever gives the player the highest total hand value <= 21)
        while ((acesNr > 0) && (handValue + 10 <= 21)) {
            handValue += 10;
            acesNr -= 1;
        }

        console.log("Total hand value: ", handValue);
        return handValue;
    }

    //  Puts all cards back in the decks, then shuffles them
    function resetDecks() private {
        console.log("Reshuffling all cards...");

        allCards = new uint8[](0);
        for (uint8 i = 0; i < 52; i++)
            for (uint8 j = 0; j < decksNr; j++)
                allCards.push(i);

        shuffleDecks();
    }

    //  TO-DO: Replace with off-chain RNG like Chainlink VRF
    function badRNG(uint max) private view returns (uint) {
        return block.timestamp % max;
    }

    //  Randomly shuffle the cards in the decks
    //  TO-DO: Change public to private, this is for debugging
    function shuffleDecks() public {
        for (uint256 i = 0; i < allCards.length; i++) {
            uint256 n = i + badRNG(allCards.length - i);
            uint8 temp = allCards[n];
            allCards[n] = allCards[i];
            allCards[i] = temp;
        }
    }

    function getCardName(uint8 cardId) public view returns (string memory) {
        return cardInfo[cardId].fullName;
    }

    //  TO-DO: Comment out, this is for debugging
    function printDecks() public view {
        console.log("Cards: ");
        for (uint i = 0; i < allCards.length; i++)
            console.log(getCardName(allCards[i]));
    }

    //  TO-DO: Change public to private, this is for debugging
    function drawCard() public returns(uint8) {
        require(allCards.length > 0, "No cards left in the deck!");

        //  Before drawing, shuffle the decks since they are not secret on the blockchain.
        //  Comment this during testing if you want to verify it draws correctly.
        // shuffleDecks();

        uint8 drawnCard = allCards[allCards.length - 1];
        allCards.pop();

        console.log("Drawn card: ", getCardName(drawnCard));
        return drawnCard;
    }


    //  TO-DO: Change public to private, this is for debugging
    function advanceTurn() public {
        currentPlayerTurn = (currentPlayerTurn + 1) % playersNr;
        console.log("CURRENT PLAYER'S TURN: ", playersInGame[currentPlayerTurn]);

        //  If this player got Blackjack at the beginning, skip their turn
        if (allPlayerStates[playersInGame[currentPlayerTurn]].gotBlackjack) {
            console.log("Skipping %s (they got Blackjack)...", playersInGame[currentPlayerTurn]);
            advanceTurn();
            return;
        }

        //  Dealer's turn - finish this round and start a new one
        if (currentPlayerTurn == 0) {
            endRound();
            startRound();
            advanceTurn();
        }
    }

    function hit(uint8 handId) external yourTurn(msg.sender) {
        uint8 drawnCard = drawCard();

        //  Add the drawn card to that hand
        allPlayerStates[msg.sender].hands[handId].push(drawnCard);

        //  Calculate the new hand value
        uint8 handValue = getHandValue(msg.sender, handId);

        if (handValue > 21) {
            console.log("BUST");
            allPlayerStates[msg.sender].bet = 0;

            advanceTurn();
        }
    }

    function stand() external yourTurn(msg.sender) {
        advanceTurn();
    }

    function double(uint8 handId) external yourTurn(msg.sender) {
        //  Double the player's bet
        allPlayerStates[msg.sender].bet *= 2;

        //  Draw a card
        uint8 drawnCard = drawCard();

        //  Add the drawn card to that hand
        allPlayerStates[msg.sender].hands[handId].push(drawnCard);

        //  Calculate the new hand value
        uint8 handValue = getHandValue(msg.sender, handId);

        if (handValue > 21) {
            console.log("BUST");
            allPlayerStates[msg.sender].bet = 0;
        }
        advanceTurn();
    }
}