pragma solidity ^0.8.30;

contract AdminOnly{
    address public owner;
    uint256 public treasureAmount;
    uint public deadline;
    mapping(address => uint256) public withdrawalAllowance;
    mapping(address => bool) public admins;

    // event 
    event TreasureAdded(uint256 amount);
    event WithdrawalApproved(address indexed recipient, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    // constructor 
    constructor(){
        owner = msg.sender;
        admins[msg.sender] = true;
    }

    // modifier 
    modifier onlyOwner(){
        require(msg.sender == owner, "Access denied");
    }
    modifier onlyAdmin(){
        require(admins[msg.sender], "Not an admin");
        _;
    }
    modifier afterDeadline(){
        require(block.timestamp > deadline, "Too early");
        _;
    }
    modifier onlyApproved(){
        require(withdrawalAllowance[msg.sender]>0, "User has no withdrawal approval");
    }
    // more gas efficient approach 
    modifier onlyApproved(){
        if(withdrawalAllowance[msg.sender] == 0) revert NotApproved();
        _;
    }

    // custom errors 
    error NotApproved();
    error InsufficientAllowance(uint256 requested, uint256 available);
    error InsufficientTreasure(uint256 requested, uint256 available);

    receive() external payable{
        treasureAmount += msg.value;
        emit TreasureAdded(msg.value);
    }

    fallback() external payable{
        treasureAmount+= msg.value;
        emit TreasureAdded(msg.value);
    }
    
    // function 
    function addTreasure() public payable onlyOwner{
        require(msg.value >0, "Must be more than 0");
        treasureAmount += msg.value;
    }

    function approveWithdrawal(address recipient, uint256 amount) public onlyOwner{
        require(amount <= treasureAmount,"Not enough treasure");
        withdrawalAllowance[recipient] = amount;
        emit WithdrawalApproved(recipient, amount);
    }

    function addAdmin(address admin) public onlyOwner{
        admins[admin] = true;
    }

    function removeAdmin(address admin) public onlyAdmin{
        require(admin != owner, "Cannot remove owner as admin");
        admins[admin] = false;
    }

    function renounceOwnership() public onlyOwner{
        owner = address(0);
        admins[address(0)] = false;
    }

    function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function withdrawTreasure(uint256 amount) public{
        if(msg.sender == owner){
           require(amount <= treasureAmount,"Not enough treasure");
           (bool success, ) =msg.sender.call{value: amount}("");
           require(success, "transaction failed");
           treasureAmount -= amount;
           emit Withdrawn(msg.sender, amount);
           return;
        }
        require(withdrawalAllowance[msg.sender] > 0, "User has no approval");
        require(amount <= withdrawalAllowance[msg.sender],"You don't have approval for this amount");
        require(amount <= treasureAmount,"Not enough treasure");
        (bool success, ) =msg.sender.call{value: amount}("");
        require(success, "transaction failed");
        withdrawalAllowance[msg.sender] -= amount;
        treasureAmount -= amount;

        emit Withdrawn(msg.sender, amount);
    }

    function checkMyAllowance() public view onlyApproved returns (uint256) {
       return withdrawalAllowance[msg.sender];
    } 

    function trasferOwnership(address newOwner) public onlyOwner{
        require(newOwner != address(0), "New Owner cannot be 0 address");
        owner = newOwner;
    }
}