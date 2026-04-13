// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30; //our solidity version 

contract ClickCounter{
    uint256 public counter;
    mapping(address => uint256) public ClicksByUser;

    event Clicked(address indexed user,uint256 NewCount);

    function click() public{
      counter++;
      ClicksByUser[msg.sender]++;
      emit Clicked(msg.sender ,counter);
    }
    function reset() public{
      uint256 userClicks = ClicksByUser[msg.sender];
      counter -= userClicks;
      ClicksByUser[msg.sender]=0;
    }
    function decrement() public{
      require(ClicksByUser[msg.sender]>0 , "caller has no clciks to decrement");
      counter--;
      ClicksByUser[msg.sender]--;
    }
}