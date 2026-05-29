// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30; //our solidity version 

contract AuctionHouse{
    address public owner; // who created the auction
    string public item;  // item at auction
    uint public auctionEndTime; // stop time
    address private highestBidder;
    uint private highestBid;
    bool public ended;
    mapping(address => uint) public bids; // current bid of everyone -almost like an orderbook 
    address[] public bidders;

    constructor(string memory _item, uint _biddingTime){
        owner = msg.sender;
        item = _item;
        auctionEndTime = block.timestamp + _biddingTime;
    }

    function bid(uint amount) external{
        require(block.timestamp < auctionEndTime, "Auction has already ended");
        require(amount >0, "Bid amount cannot be 0");
        require(amount > bids[msg.sender], "New bids must be higher than your current bid");

        if(bids[msg.sender] == 0){
            bidders.push(msg.sender);
        }

        bids[msg.sender] = amount;
        if(amount> highestBid){
            highestBid = amount;
            highestBidder = msg.sender;
        }
    }

    function endAuction(){
       require( block.timestamp >= auctionEndTime,"Auction hasn't ended yet");
       require(!ended, "Auction end already called");
       ended = true;
    }

    function getWinner() external view returns(address, uint){
        require(ended, "the auction has not ended");
        return (highestBidder, highestBid);
    }


}