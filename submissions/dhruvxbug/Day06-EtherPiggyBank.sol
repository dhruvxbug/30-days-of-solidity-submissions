pragma solidity ^0.8.30;
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract EtherPiggyBank is ReentrancyGuard{
    address public bankManager;
    address[] public users; 
    mapping(address => bool) public registeredMembers;
    mapping(address => uint256) balance;

    constructor(){
        bankManager = msg.sender;
        members.push(msg.sender);
    }

    modifier OnlyBankManager(){
        require(msg.sender == bankManager,"Access denied");
        _;
    }
    modifier onlyRegisteredMember(){
        require(registeredMembers[msg.sender],"Member not registered");
        _;
    }

    function addMembers(address _member) public OnlyBankManager{
        require(_member != address(0), "Invalid address");
        require(_member != msg.sender,"Manager is already a member");
        require(!registeredMembers[_member],"Member already registered");

        registeredMembers[_member] =true;
        members.push(_member);
    }

    function getMembers()public view returns(address[] memory){
        return members;
    }

    function deposit() public payable onlyRegisteredMember{
        require(msg.value > 0, "Invalid amount");
        balance[msg.sender] += msg.value;
    }

    function withdrawEther(uint256 _amount) public nonReentrant onlyRegisteredMember{
        require(_amount >0,"amount cannot be 0");
        require(balance[msg.sender] >= _amount, "Cannot wityhdraw more than your acc balance");
        // always reduce amount before actual transactions - reentrancy attack
        balance[msg.sender] -= _amount;
        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success, "Transaction failed");
    }

    function checkContractBalance() public view returns(uint256){
        return address(this).balance;
    }

    function checkUserBalance() public view onlyRegisteredMember returns(uint256 ){
       return balance[msg.sender];
    }

}