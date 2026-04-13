// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31; //our solidity version 

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
      counter =0;
    }
    function decrement() public{
      require(counter>0 , "counter is already at 0");
      counter--;
      ClicksByUser[msg.sender]--;
    }
}