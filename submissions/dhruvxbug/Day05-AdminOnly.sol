pragma solidity ^0.8.30;

contract AdminOnly{
    address public owner;
    uint256 public treasureAmount;
    uint256 public deadline;
    mapping(address => uint256) public withdrawalAllowance;
    mapping(address => bool) public admins;
    mapping(address => uint256) public userWithdrawalCount;
    mapping(address => uint256[]) public userWithdrawalIndices;

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

    // event 
    event TreasureAdded(uint256 amount);
    event WithdrawalApproved(address indexed recipient, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    // new event for withdrawal history tracking 
    event WithdrawalInitiated(address indexed user, uint256 amount, uint256 timestamp);
    event WithdrawalCompleted(address indexed user, uint256 amount, uint256 timestamp);
    event WithdrawalFailed(address indexed user, uint256 amount, string reason, uint256 timestamp);
    event WithdrawalApprovalUsed(address indexed user, uint256 amount, uint256 remainingAllowance);
    
    event WithdrawalDetails(
        address indexed user,
        uint256 amount,
        uint256 timestamp,
        string withdrawalType,      // "owner","approved","partial"
        uint256 newTreasureAmount,
        uint256 newAllowance
    )

    struct WithdrawalRecord{
        address user;
        uint256 amount;
        uint256 timestamp;
        bool success;
        string withdrawalType; 
    }

    WithdrawalRecord[] public withdrawalHistory;

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
    
    // functions
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
        uint256 timestamp = block.timestamp;
        string memory withdrawalType;
        bool success = false;

        emit WithdrawalInitiated(msg.sender, amount, timestamp);

        if(msg.sender == owner){
           withdrawalType = "owner";

           if(amount > treasureAmount){
            emit WithdrawalFailed(msg.sender, amount, "Not enough Treasure", timestamp);
            revert InsufficientTreasure(amount, treasureAmount);
           }

           if(amount > address(this).balance){
            emit WithdrawalFailed(msg.sender, amount,"Insufficient balance",timestamp);
            revert("Not enough ETH in the contract");
           }

           // new way of doing it 
           (bool success, ) =msg.sender.call{value: amount}("");
           require(success, "transaction failed");
           // old way 
           payable(msg.sender).transfer(amount);
           success = true;

           treasureAmount -= amount;
           emit WithdrawalCompleted(msg.sender, amount, timestamp);
           emit WithdrawalDetails(msg.sender, amount, timestamp, withdrawalType,
            treasureAmount, withdrawalAllowance[msg.sender]);
        } else{
            if(withdrawalAllowance[msg.sender] == 0){
                emit WithdrawalFailed(msg.sender, amount, "Amount exceeds allowance", timestamp);
                revert InsufficientAllowance(amount, withdrawalAllowance[msg.sender]);
            }
            if(amount > treasureAmount){
                emit WithdrawalFailed(msg.sender, amount, "Amount exceeds the Treasure balance", timestamp);
                revert InsufficientTreasure(amount, treasureAmount);
            }
            if(amount > address(this).balance){
                emit WithdrawalFailed(msg.sender, amount, "Not enough ETH in contract", timestamp);
                revert("Not enough ETH in contract")
            }

            withdrawalType = "approved";
            uint256 oldAllowance = withdrawalAllowance[msg.sender];

            (bool success, ) =msg.sender.call{value: amount}("");
            require(success, "transaction failed");
            withdrawalAllowance[msg.sender] -= amount;
            treasureAmount -= amount;
    
            emit WithdrawalCompleted(msg.sender, amount, timestamp);
            emit WithdrawalApprovalUsed(msg.sender, amount, withdrawalAllowance[msg.sender])
            emit WithdrawalDetails(msg.sender, amount, timestamp, withdrawalType,
            treasureAmount, withdrawalAllowance[msg.sender]);
        }

        _addToWithdrawalHistory(msg.sender, amount, timestamp, success, withdrawalType);
    }

    function withdrawFullAllowance() public onlyApproved{
        uint256 amount = withdrawalAllowance[msg.sender];
        uint256 timestamp = block.timestamp;

        if(amount == 0){
          emit WithdrawalFailed(msg.sender, amount,"Withdrawal amount cannot be 0", timestamp);
        }
        if(amount>treasureAmount){
          emit WithdrawalFailed(msg.sender, amount,"Insufficient treasure", timestamp);
        }
        if(amount> address(this).balance){
          emit WithdrawalFailed(msg.sender, amount,"Insufficient ETH in contract", timestamp);
        }
        
        treasureAmount -= amount;
        withdrawalAllowance[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value:amount}("");
        require(success, "Transaction failed");

        emit WithdrawalCompleted(msg.sender, amount, timestamp);
        emit WithdrawalDetails(
            msg.sender, amount, timestamp, "full_allowance", treasureAmount, 0
        );
        _addToWithdrawalHistory(msg.sender, amount, timestamp, true, "full_allowance");
    }

    // internal function
    function _addToWithdrawalHistory(
        address user,
        uint256 amount,
        uint256 timestamp,
        bool success,
        string memory withdrawalType
    ) internal {
        withdrawalHistory.push(WithdrawalRecord({
            user: user,
            amount: amount,
            timestamp: timestamp,
            success: success,
            withdrawalType: withdrawalType
        }));

        uint256 index = withdrawalHistory.length -1;
        userWithdrawalIndices[user].push(index);
        userWithdrawalCount[user]++;
    } 

    function getTotalWithdrawalCount()public view returns(uint256){
        return withdrawalHistory.length;
    }  

    function getUserWithdrawalCount(address user) public view returns (uint256){
        return userWithdrawalCount[user];
    }

    function getUserWithdrawalHistory(address user) public view returns(WithdrawalRecord[] memory){
        uint256 count = userWithdrawalCount[user];
        // dynamic array in memory to hold user's withdrawal record, size =count 
        WithdrawalRecord[] memory userHistory = new WithdrawalRecord[](count);

        uint256[] storage indices = userWithdrawalIndices[user];
        for(uint256 i=0; i<count; i++){
            userHistory[i] = withdrawalHistory[indices[i]];
        }
        return userHistory;
    }

    function checkMyAllowance() public view onlyApproved returns (uint256) {
       return withdrawalAllowance[msg.sender];
    } 

    function trasferOwnership(address newOwner) public onlyOwner{
        require(newOwner != address(0), "New Owner cannot be 0 address");
        owner = newOwner;
    }
}

contract WithdrawalHistoryIndexer{
    mapping(address => uint256[]) public userWithdrawalTimestamps;

    function indexWithrawal(address user, uint256 timestamp) external{
        userWithdrawalTimestamps[user].push(timestamp);
    }
}