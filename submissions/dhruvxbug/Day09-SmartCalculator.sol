// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ScientificCalculator.sol";

contract Calculator {
    address public owner;
    address public scientificCalculatorAddress;
    mapping(address => bool) public authorizedUsers;
    bool public paused;

    event ScientificCalculatorSet(address indexed newAddress);
    event UserAuthorized(address indexed user);
    event UserRevoked(address indexed user);
    event ContractPaused(bool indexed paused);

    constructor() {
        owner = msg.sender;
        authorizedUsers[owner] = true;
        paused = false;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }

    modifier onlyAuthorized() {
        require(authorizedUsers[msg.sender], "Unauthorized user");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    // ==== Access control ====
    function setScientificCalculator(address _address) public onlyOwner whenNotPaused{
        scientificCalculatorAddress = _address;
        emit ScientificCalculatorSet(_address);
    }

    function authorizedUsers(address _user) public onlyOwner{
       authorizedUsers[_user] = true;
       emit UserAuthorized(_user);
    }

    function revokeUser(address _user) public onlyOwner{
        authorizedUsers[_user] = false;
        emit UserRevoked(_user);
    }

    function togglePause() public onlyOwner{
        paused = !paused;
        emit ContractPaused(paused);
    }

    // === basic operations ===
    function add(uint256 a, uint256 b) public pure returns (uint256) {
        return a + b;
    }

    function subtract(uint256 a, uint256 b) public pure returns (uint256) {
        return a - b;
    }

    function multiply(uint256 a, uint256 b) public pure returns (uint256) {
        return a * b;
    }

    function divide(uint256 a, uint256 b) public pure returns (uint256) {
        require(b != 0, "Cannot divide by zero");
        return a / b;
    }

    // === advanced operations ===
    function modulo(uint256 a, uint256 b) public pure returns (uint256) {
        require(b != 0, "Cannot modulo by zero");
        return a % b;
    }

    function power(uint256 base, uint256 exponent) public pure returns (uint256) {
        return base ** exponent;
    }

    function authorizeDataModifier(address _user) public{ 
        require(msg.sender == address(this) || msg.sender == tx.origin, "Not Authorized");
        canModifyData[_user] = true;
    }

    // INTERFACE CALL
    function calculatePower(uint256 base, uint256 exponent) public view returns (uint256) {
        ScientificCalculator scientificCalc = ScientificCalculator(scientificCalculatorAddress);
        return scientificCalc.power(base, exponent);
    }

    // LOW-LEVEL CALL
    function calculateSquareRoot(uint256 number) public returns (uint256) {
        bytes memory data = abi.encodeWithSignature("squareRoot(uint256)", number);
        (bool success, bytes memory returnData) = scientificCalculatorAddress.call(data);
        require(success, "External call failed");
        return abi.decode(returnData, (uint256));
    }
}