// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30; //our solidity version 

contract AuctionHouse{
    address public owner; // who created the auction
    string public item;  // item at auction
    uint public auctionEndTime; // stop time
    address private highestBidder;
    uint private highestBid;
    bool public ended;
    //old logic mapping
    mapping(address => uint) public bids; // current bid of everyone -almost like an orderbook 
    address[] public bidders;
    // new logic mapping 
    mapping(address => uint) public pendingRefunds;
    uint public reservePrice;
    bool public auctionSuccessful;

    // events
    event BidPlaced(address indexed bidder, uint amount);
    event AuctionEnded(bool success, address winner, uint winningBid);
    event RefundSent(address indexed bidder, uint amount);
    event OwnerWithdrawn(address indexed address, uint amount);
    event ReserveNotMet(uint reservePrice, uint highestBid);

    constructor(string memory _item, uint _biddingTime, uint _reservePrice){
        owner = msg.sender;
        item = _item;
        auctionEndTime = block.timestamp + _biddingTime;
        reservePrice = _reservePrice;
        require(_reservePrice > 0; "Reserve price should be greater than 0");
    }

    function bid() external payable{
        require(block.timestamp < auctionEndTime, "Auction has already ended");
        require(msg.value >0, "Bid amount cannot be 0");
        require(msg.value > highestBid, "New bids must be higher than the current highest bid");

        // new bidder 
        if(pendingRefunds[msg.sender] == 0 && msg.sender != highestBidder){
            bidders.push(msg.sender);
        }

        // new logic 
        address previousHighestBidder = highestBidder;
        uint previousHighestBid = highestBid;

        if(previousHighestBidder != address(0)){
            pendingRefunds[previousHighestBidder] += previousHighestBid;
        }

        highestBidder = msg.sender;
        highestBid = msg.value;

        emit BidPlaced(msg.sender, msg.value);
    }

    function withdrawRefund() external{
        uint refundAmount = pendingRefunds[msg.sender];
        require(refundAmount > 0, "No refund available");

        pendingRefunds[msg.sender] =0;

        // .call or .trasfer both are valid 
        (bool success, ) = msg.sender.call{value: refundAmount}("");
        require(success, "refund failed");

        emit RefundSent(msg.sender, refundAmount);
    }

    function endAuction(){
       require( block.timestamp >= auctionEndTime,"Auction hasn't ended yet");
       require(!ended, "Auction end already called");
       ended = true;

      if (highestBid >= reservePrice){
        auctionSuccessful = true;
        emit AuctionEnded(true, highestBidder, highestBid);
      } else {
        auctionSuccessful = false; 
        emit AuctionEnded( false, address(0), 0);
        emit ReserveNotMet(reservePrice, highestBid);
      }
    }

    function withdrawFailedAuctionRefund() external{
        require(ended, "Auction is still active");
        require(!auctionSuccessful, "Auction successful use withdrawRefund()");

        uint refundAmount = pendingRefunds[msg.sender];

        if(msg.sender == highestBidder){
            refundAmount += highestBid;
            pendingRefunds[msg.sender] = 0;
        }else if(refundAmount>0){
            pendingRefunds[msg.sender] = 0;
        } 

        (bool success, ) = msg.sender.call{value: refundAmount}("");
        require(success, "Refund failed");

        emit RefundSent(msg.sender, refundAmount);
    }

    // new - withdrawal for the contract creator (auction manager)
    function withdrawWinningBid() external{ 
        require(ended, "Auction hasn't ended yet");
        require(auctionSuccessful, "Auction failed");
        require(msg.sender == owner, "Only owner can withdraw");
        require(address(this).balance >0, "No funds to withdraw");

        uint amount = address(this).balance;

        (bool success, ) = owner.call{value: amount}("");
        require(success, "Withdrawal failed");

        emit OwnerWithdrawn(owner, amount);
    }

    function getWinner() external view returns(address, uint){
        require(ended, "the auction has not ended");
        if (!auctionSuccessful) {
            return (address(0), 0, false);
        }
        return (highestBidder, highestBid, true);
    }

    function getContractBalance() external view returns(uint){
        return address(this).balance;
    }

    function getMyPendingRefund() external view returns(uint){
        return pendingRefunds[msg.sender];
    }

    function isReserveMet() public view returns(bool){
        return highestBid >= reservePrice;
    }
}