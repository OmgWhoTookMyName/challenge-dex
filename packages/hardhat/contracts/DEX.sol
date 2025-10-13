// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DEX Template
 * @author stevepham.eth and m00npapi.eth
 * @notice Empty DEX.sol that just outlines what features could be part of the challenge (up to you!)
 * @dev We want to create an automatic market where our contract will hold reserves of both ETH and 🎈 Balloons.
 * These reserves will provide liquidity that allows anyone to swap between the assets.
 *
 * NOTE: functions outlined here are what work with the front end of this challenge.
 * Also return variable names need to be specified exactly may be referenced (It may be helpful to cross reference with front-end code function calls).
 */
contract DEX {
    /* ========== GLOBAL VARIABLES ========== */

    IERC20 token; //instantiates the imported contract
    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidity;

    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when ethToToken() swap transacted
     */
    event EthToTokenSwap(address swapper, uint256 tokenOutput, uint256 ethInput);

    /**
     * @notice Emitted when tokenToEth() swap transacted
     */
    event TokenToEthSwap(address swapper, uint256 tokensInput, uint256 ethOutput);

    /**
     * @notice Emitted when liquidity provided to DEX and mints LPTs.
     */
    event LiquidityProvided(address liquidityProvider, uint256 liquidityMinted, uint256 ethInput, uint256 tokensInput);

    /**
     * @notice Emitted when liquidity removed from DEX and decreases LPT count within DEX.
     */
    event LiquidityRemoved(
        address liquidityRemover,
        uint256 liquidityWithdrawn,
        uint256 tokensOutput,
        uint256 ethOutput
    );

    /* ========== CONSTRUCTOR ========== */

    constructor(address tokenAddr) {
        token = IERC20(tokenAddr); //specifies the token address that will hook into the interface and be used through the variable 'token'
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice initializes amount of tokens that will be transferred to the DEX itself from the erc20 contract mintee (and only them based on how Balloons.sol is written). Loads contract up with both ETH and Balloons.
     * @param tokens amount to be transferred to DEX
     * @return totalLiquidity is the number of LPTs minting as a result of deposits made to DEX contract
     * NOTE: since ratio is 1:1, this is fine to initialize the totalLiquidity (wrt to balloons) as equal to eth balance of contract.
     */
    function init(uint256 tokens) public payable returns (uint256) {
        require(totalLiquidity == 0, "Liquidity already provided");
        uint256 totalCalcLiquidity = token.balanceOf(address(this)) + tokens;
        //Take balloon from sender
        require(token.transferFrom(msg.sender, address(this), tokens),"Could not transfer tokens");
        totalLiquidity = address(this).balance;
        liquidity[msg.sender] = totalLiquidity;
        emit LiquidityProvided(msg.sender, totalCalcLiquidity, msg.value, liquidity[msg.sender]);

        return totalLiquidity;
    }

    /**
     * @notice returns yOutput, or yDelta for xInput (or xDelta)
     * @dev Follow along with the [original tutorial](https://medium.com/@austin_48503/%EF%B8%8F-minimum-viable-exchange-d84f30bd0c90) Price section for an understanding of the DEX's pricing model and for a price function to add to your contract. You may need to update the Solidity syntax (e.g. use + instead of .add, * instead of .mul, etc). Deploy when you are done.
     */
    function price(uint256 xInput, uint256 xReserves, uint256 yReserves) public pure returns (uint256 yOutput) {
        uint256 threepercentOfX = (xInput * 3) / 1000; //calc 0.3% fee
        uint256 xInputLessFee = xInput - (threepercentOfX); //Take fee
        uint256 k = xReserves * yReserves;
        uint256 yDelta = yReserves * 1000 - (k * 1000 / (xReserves + xInputLessFee));
        uint256 yOut = yDelta / 1000;
        console.log("Fee calculated to be: %s, after fee input: %s at a k value of: %s", threepercentOfX, xInputLessFee, k);
        return yOut;
    }

    /**
     * @notice returns liquidity for a user.
     * NOTE: this is not needed typically due to the `liquidity()` mapping variable being public and having a getter as a result. This is left though as it is used within the front end code (App.jsx).
     * NOTE: if you are using a mapping liquidity, then you can use `return liquidity[lp]` to get the liquidity for a user.
     * NOTE: if you will be submitting the challenge make sure to implement this function as it is used in the tests.
     */
    function getLiquidity(address lp) public view returns (uint256) {
        return liquidity[lp];
    }

    /**
     * @notice sends Ether to DEX in exchange for $BAL
     */
    function ethToToken() public payable returns (uint256 tokenOutput) {
        require(msg.value > 0, "Must input some eth");

        uint256 buyableTokens = price(msg.value, address(this).balance - msg.value, token.balanceOf(address(this)));

        require(token.transfer(msg.sender, buyableTokens),"Unable to swap");
        emit EthToTokenSwap(msg.sender, buyableTokens, msg.value);
        return buyableTokens;
    }

    /**
     * @notice sends $BAL tokens to DEX in exchange for Ether
     */
    function tokenToEth(uint256 tokenInput) public returns (uint256 ethOutput) {

        require(tokenInput > 0, "Must supply some tokens");
        //Calculate how much eth to send to sender
        uint256 ethValue = price(tokenInput, token.balanceOf(address(this)), address(this).balance);
        //First transfer the tokens from the sender
        uint256 allowedTokens = token.allowance(msg.sender, address(this));
        require(allowedTokens >= tokenInput,"Not enough token allowance");
        require(token.transferFrom(msg.sender, address(this), tokenInput), "Could not take tokens from user");
        totalLiquidity += tokenInput;

        (bool sent,) = msg.sender.call{value: ethValue}("");
        require(sent, "Failed to send Ether");

        emit TokenToEthSwap(msg.sender, tokenInput, ethValue);
        return ethValue;
    }

    /**
     * @notice allows deposits of $BAL and $ETH to liquidity pool
     * NOTE: parameter is the msg.value sent with this function call. That amount is used to determine the amount of $BAL needed as well and taken from the depositor.
     * NOTE: user has to make sure to give DEX approval to spend their tokens on their behalf by calling approve function prior to this function call.
     * NOTE: Equal parts of both assets will be removed from the user's wallet with respect to the price outlined by the AMM.
     */
    function deposit() public payable returns (uint256 tokensDeposited) {
        
        require(msg.value > 0, "Must deposit some ETH");
        //Calculate how much BAL should be extracted
        //First we need eth reserve pre deposit from this transaction
        uint256 ethRes = address(this).balance - msg.value;
        //This is just the ratio that the market maker set when they set-up the pool
        //However this ratio can change based on buys and sells of the token
        uint256 tokens = ((msg.value * token.balanceOf(address(this))) / ethRes) + 1;

        //Check to make sure user has set-up allowances
        uint256 allowed = token.allowance(msg.sender, address(this));

        require(allowed >= tokens, "Insufficient allowance");

        require(token.transferFrom(msg.sender, address(this), tokens), "Could not transfer tokens from user");

        //Every set of new pairs contributes 1 liquidity that mints
        uint lptMint = msg.value * totalLiquidity / ethRes;
        totalLiquidity += lptMint;
        liquidity[msg.sender] += lptMint;

        emit LiquidityProvided(msg.sender, lptMint, msg.value, tokens);

        return tokens;

    }

    /**
     * @notice allows withdrawal of $BAL and $ETH from liquidity pool
     * NOTE: with this current code, the msg caller could end up getting very little back if the liquidity is super low in the pool. I guess they could see that with the UI.
     */
    function withdraw(uint256 amount) public returns (uint256 ethAmount, uint256 tokenAmount) {


        //Should be able to withdraw based on LPT a user has
        //Get users LPT
        uint256 userLpt = getLiquidity(msg.sender);

        require(amount <= userLpt, "User cannot withdraw more than is owned");

        uint256 ethTotal = amount * (address(this).balance / token.balanceOf(address(this)));

        uint256 tokenTotal = amount * (token.balanceOf(address(this)) / address(this).balance);

        totalLiquidity -= amount;
        liquidity[msg.sender] -= amount;

        require(token.transfer(msg.sender, tokenTotal), "Unable to complete token transfer to user");
        (bool sent,) = msg.sender.call{value: ethTotal}("");
        require(sent, "Failed to send Ether");
        emit LiquidityRemoved(msg.sender, amount, tokenTotal, ethTotal);
        return (ethTotal, tokenTotal);
    }
}
