// SPDX-License-Identifier: MIT
// custom ERC 20 before actual ERC20 
pragma solidity ^0.8.20;

contract SimpleERC20 {
    string public name = "SimpleToken";
    string public symbol = "SIM";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    address public owner;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Minted(address indexed minter, uint256 amount);
    event Burned(address indexed minter, uint256 amount);
    event FeeCharged(address indexed from, uint256 feeAmount);
    event SnapshotTaken(uint256 indexed snapshotId);
    event VestingClaimed(address indexed user, uint256 amount);

    struct Vesting{
        uint256 totalAllocation;
        uint256 claimed;
        uint256 start;
        uint256 duration;
        bool revoked;
    }
    mapping(address => Vesting) public userVesting;

    struct Snapshot{
        uint256 timestamp;
        uint256 totalSupply;
        mapping(address => uint256) balances;
    }
    uint256 public snapshotCount;
    mapping(uint256 => Snapshot) public snapshots;
    mapping(uint256 => mapping(address => bool)) public hasSnapshotBalance;

    constructor(uint256 _initialSupply) {
        owner = msg.sender;
        totalSupply = _initialSupply * (10 ** uint256(decimals));
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    modifier onlyOwner(){
        require(msg.sender == owner, "not owner");
        _;
    }

    function transfer(address _to, uint256 _value) public returns (bool) {
        require(balanceOf[msg.sender] >= _value, "Not enough balance");
        _transfer(msg.sender, _to, _value);
        return true;
    }

    function approve(address _spender, uint256 _value) public returns (bool) {
        allowance[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public returns (bool) {
        require(balanceOf[_from] >= _value, "Not enough balance");
        require(allowance[_from][msg.sender] >= _value, "Allowance too low");
        allowance[_from][msg.sender] -= _value;
        _transfer(_from, _to, _value);
        return true;
    }

    function _transferWithFees(address _from, address _to, uint256 _value) internal{
        require(_to != address(0), "Invalid address");

        uint256 feeAmount = 0;
        uint256 burnAmount = 0;
        uint256 transferAmount = _value;

        if (feesEnabled && feePercent > 0 && _from != owner) {
            feeAmount = (_value * feePercent) / 100;
            transferAmount -= feeAmount;
        }
        if (deflationaryEnabled && burnPercent > 0 && _from != owner) {
            burnAmount = (_value * burnPercent) / 1000; // 0.5% = 5/1000
            transferAmount -= burnAmount;
        }

        balanceOf[_from] -= _value;
        if(transferAmount > 0){
            balanceOf[_to] += transferAmount;
            emit Transfer(_from, _to, transferAmount);
        }
        if(feeAmount >0){
            balanceOf[feeWallet] += feeAmount;
            emit Transfer(_from, feeWallet, feeAmount);
            emit FeeCharged(_from, feeAmount);
        }
        if(burnAmount >0){
            balanceOf[_from] -= burnAmount;
            totalSupply -= burnAmount;
            emit Transfer(_from, address(0), burnAmount);
            emit Burned(_from, burnAmount);
        }
    }

    function _transfer(address _from, address _to, uint256 _value) internal {
        require(_to != address(0), "Invalid address");
        balanceOf[_from] -= _value;
        balanceOf[_to] += _value;
        emit Transfer(_from, _to, _value);
    }

    function mint(uint256 amount) public onlyOwner{
        require(msg.sender != address(0), "Address cannot be 0");
        require(amount != 0, "Amount cannot be 0");
        balanceOf[msg.sender] += amount;
        totalSupply += amount;
        emit Minted(address(0), msg.sender, amount)
    }

    function burn(uint256 amount) public{
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        require(amount != 0, "Amount cannot be 0");
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        emit Burned(msg.sender, amount);
    }

    function setFeePercent(uint256 _feePercent) public onlyOwner {
        require(_feePercent <= 10, "Fee too high (max 10%)");
        feePercent = _feePercent;
    }

    function setFeeWallet(address _feeWallet) public onlyOwner {
        require(_feeWallet != address(0), "Invalid wallet");
        feeWallet = _feeWallet;
    }

    function toggleFees() public onlyOwner {
        feesEnabled = !feesEnabled;
    }

    function setBurnPercent(uint256 _burnPercent) public onlyOwner {
        require(_burnPercent <= 50, "Burn too high (max 5%)");
        burnPercent = _burnPercent;
    }

    function claimVested() public {
      Vesting storage v = vestings[msg.sender];
      require(v.totalAllocation > 0, "No vesting schedule");
      require(!v.revoked, "Vesting revoked");
      require(block.timestamp >= v.start, "Vesting not started");
  
      uint256 elapsed = block.timestamp - v.start;
      if (elapsed > v.duration) {
          elapsed = v.duration;
      }
      uint256 vested = (v.totalAllocation * elapsed) / v.duration;
      uint256 claimable = vested - v.claimed;
      require(claimable > 0, "Nothing to claim");
  
      v.claimed += claimable;
      balanceOf[msg.sender] += claimable;
   
      emit Transfer(address(0), msg.sender, claimable);
      emit VestingClaimed(msg.sender, claimable);
    }

    function createVestingSchedule(
        address _beneficiary,
        uint256 _totalAllocation,
        uint256 _start,
        uint256 _duration,
        uint256 _cliff
    ) public onlyOwner{
      require(_beneficiary != address(0),"Invalid");
      require(_totalAllocation > 0, "Allocation must be > 0");
      require(_duration > 0, "Duration must be > 0");
      require(vestingSchedules[_beneficiary].totalAllocation == 0, "Vesting already exists");

      vestingSchedules[_beneficiary] = VestingSchedule({
        totalAllocation: _totalAllocation,
        claimed: 0,
        start: _start,
        duration: _duration,
        cliff: _cliff,
        revoked: false
      });
    }

    function revokeVesting(address _beneficiary) public onlyOwner{
        VestingSchedule storage v =vestingSchedules[_beneficiary];
        require(v.totalAllocation > 0, "No vesting schedule");
        require(!v.revoked, "Already revoked");

        v.revoked = true;
        uint256 unclaimed = v.totalAllocation - v.claimed;
        if(unclaimed>0){
            balanceOf[owner] += unclaimed;
        }
    }

    function getVestedAmount(address _beneficiary) public view returns (uint256) {
        VestingSchedule storage v = vestingSchedules[_beneficiary];
        if (v.totalAllocation == 0 || v.revoked) return 0;
        if (block.timestamp < v.start + v.cliff) return 0;
        
        uint256 elapsed = block.timestamp - v.start;
        if (elapsed > v.duration) elapsed = v.duration;
        
        return (v.totalAllocation * elapsed) / v.duration - v.claimed;
    }

    function takeSnapshot() public onlyOwner {
        uint256 snapshotId = snapshotCount++;
        Snapshot storage newSnapshot = snapshots[snapshotId];
        newSnapshot.timestamp = block.timestamp;
        newSnapshot.totalSupply = totalSupply;
        
        // We can't store all balances efficiently in a simple mapping
        // This is a simplified version - in production, use merkle trees or external storage
        emit SnapshotTaken(snapshotId);
    }

    function getSnapshotTotalSupply(uint256 _snapshotId) public view returns (uint256) {
        require(_snapshotId < snapshotCount, "Invalid snapshot");
        return snapshots[_snapshotId].totalSupply;
    }

    function getSnapshotTimestamp(uint256 _snapshotId) public view returns (uint256) {
        require(_snapshotId < snapshotCount, "Invalid snapshot");
        return snapshots[_snapshotId].timestamp;
    }

    function renounceOwnership() public onlyOwner {
        owner = address(0);
    }
}