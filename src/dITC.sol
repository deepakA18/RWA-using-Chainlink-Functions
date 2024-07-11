//SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.25;

import {ConfirmedOwner} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";

import {FunctionsClient} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {AggregatorV3Interface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";


contract dMrsf is ConfirmedOwner,FunctionsClient,ERC20{

    using FunctionsRequest for FunctionsRequest.Request;
    using Strings for uint256;
//0xC43081d9EA6d1c53f1F0e525504d47Dd60de12da MRSF
    error dMrsf__NotEnoughCollateral();
    error dMrsf__DoesntMeetMinimalWithdrawalAmount();
    

    uint256 private constant PRECISION = 1e18;

    address constant SEPOLIA_USDC = ;
    address private constant SEPOLIA_FUNCTIONS_ROUTER = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    address private constant SEPOLIA_MRSF_PRICE_FEED = 0xc59E3633BAAC79493d908e63626716e204A45EdF;
    uint32 private constant GAS_LIMIT = 300_000;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 constant COLLATERAL_RATIO = 200;
    uint256 constant COLLATERAL_PRECISION = 100;
    bytes32 private constant DON_ID = hex"66756e2d657468657265756d2d6d61696e6e65742d3100000000000000000000";
    uint64 immutable i_subId;
    uint256 constant MINIMUM_WITHDRAWAL_AMOUNT = 100e18;
    address constant SEPOLIA_USDC_PRICEFEED = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;

    enum MintOrRedeem{
        mint,
        redeem
    }

    struct dMrsfRequest{
        uint256 amountOfTokens;
        address requester;
        MintOrRedeem mintOrRedeem;
    }

    string private s_mintSourceCode;
    string private s_redeemSourceCode;
    uint256 private s_portfolioBalance;
    mapping(bytes32 requestId => dMrsfRequest request) private s_requestIdToRequest;
    mapping(address user => uint256 pendingWithdrawlAmount) private s_userToWithdrawlAmount;
    
    
    constructor(string memory mintSourceCode,uint64 subId, string memory redeemSourceCode) ConfirmedOwner(msg.sender) FunctionsClient(SEPOLIA_FUNCTIONS_ROUTER) ERC20("dMRSF","dMRSF"){
        s_mintSourceCode = mintSourceCode;
        i_subId = subId;
        s_redeemSourceCode = redeemSourceCode;
    }

    function sendMintRequest(uint256 amount) external onlyOwner returns(bytes32){
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(s_mintSourceCode);
        bytes32 requestId = _sendRequest(req.encodeCBOR(), i_subId, GAS_LIMIT, DON_ID);
        s_requestIdToRequest[requestId] = dMrsfRequest(amount,msg.sender,MintOrRedeem.mint);
        return requestId;
    }

    //Return how much MRSF value in (INR) is stored in our brokerage
    //If we have enough MRSF value mint the token
    function _mintFulFillRequest(bytes32 requestId,bytes memory response) internal {
        uint256 amountOfTokenToMint = s_requestIdToRequest[requestId].amountOfTokens;
        s_portfolioBalance = uint256(bytes32 (response));

        //how much MRSF in the INR do we have?
        //how much MRSF in INR are we minting?
        if(_getCollateralAdjustedTotalBalance(amountOfTokenToMint) > s_portfolioBalance)
        {
            revert dMrsf__NotEnoughCollateral();
        }

        if(amountOfTokenToMint != 0)
        {
            _mint(s_requestIdToRequest[requestId].requester, amountOfTokenToMint);
        }
    }

    function sendRedeemRequest(uint256 amountdMrsf) external {
        uint256 amountdMrsfInUsdc = getUsdcvalueOfUsd(getUsdValueOfMrsf(amountdMrsf));
    
        if(amountdMrsfInUsdc < MINIMUM_WITHDRAWAL_AMOUNT)
        {
            revert dMrsf__DoesntMeetMinimalWithdrawalAmount();
        }

         FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(s_redeemSourceCode);

        string[] memory args = new string[](2);
        args[0] = amountdMrsf.toString();
        args[1] = amountdMrsfInUsdc.toString();
        req.setArgs(args);

        bytes32 requestId = _sendRequest(req.encodeCBOR(), i_subId, GAS_LIMIT, DON_ID);
        s_requestIdToRequest[requestId] = dMrsfRequest(amountdMrsf,msg.sender,MintOrRedeem.redeem);
    
        _burn(msg.sender, amountdMrsf);
    }


    function _redeemFulfillRequest(bytes32 requestId, bytes memory response) internal {
        uint256 usdcAmount = uint256(bytes32(response));
        if(usdcAmount == 0)
        {
            uint256 amountOfdMrsfBurned = s_requestIdToRequest[requestId].amountOfTokens;
            _mint(s_requestIdToRequest[requestId].requester, amountOfdMrsfBurned);
            return;
        }

        s_userToWithdrawlAmount[s_requestIdToRequest[requestId].requester] += usdcAmount;
    }

    function withdrawlAmount() external {
        s_userToWithdrawlAmount[msg.sender] = 0;

    }
    //Chainlink oracle will always response with fulfillRequest no matter what function you call:
    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory ) internal override{
        if(s_requestIdToRequest[requestId].mintOrRedeem == MintOrRedeem.mint)
        {
            _mintFulFillRequest(requestId,response);
        }
        else{
            _redeemFulfillRequest(requestId,response);
        }
    }

    function _getCollateralAdjustedTotalBalance(uint256 amountOfTokensToMint) view internal returns(uint256) {
        uint256 calculatedNewTotalValue = getCalculatedNewTotalValue(amountOfTokensToMint);
        calculatedNewTotalValue * COLLATERAL_RATIO / COLLATERAL_PRECISION;
    }

    //The new expected total value in INR of all the dMRSF tokens combined
    function getCalculatedNewTotalValue(uint256 addedNumberOfTokens) internal view returns(uint256) {
        return ((totalSupply() + addedNumberOfTokens) * getMrsfPrice()) / PRECISION;
    }


    function getUsdcvalueOfUsd(uint256 usdAmount) public view returns(uint256) {
        return(usdAmount * getUsdcPrice())/ PRECISION;
    }

    function getUsdValueOfMrsf(uint256 mrsfAmount) public view returns(uint256){
        return (mrsfAmount & getMrsfPrice()) / PRECISION;
    }

    function getMrsfPrice() public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(SEPOLIA_MRSF_PRICE_FEED);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return uint256(price) * ADDITIONAL_FEED_PRECISION;
    
    }

    function getUsdcPrice() public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(SEPOLIA_USDC_PRICEFEED);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return uint256(price) * ADDITIONAL_FEED_PRECISION;
    }
    
}