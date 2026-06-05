pragma solidity ^0.8.30;

contract AdminOnly{
    address public owner;
    uint256 public treasureAmount;
    uint256 public deadline;
    mapping(address => uint256) public withdrawalAllowance;
    mapping(address => bool) public admins;
    mapping(address => uint256) public userWithdrawalCount;
    mapping(address => uint256[]) public userWithdrawalIndices;
    mapping(address => UserInfo) public userInfo;
    mapping(Role => TierLimits) public tierLimits;
    mapping(address => mapping(uint256 => uint256)) public dailyWithdrawn;
    mapping(address => uint256) public lastWithdrawalTime;

    address[] public ownerList;
    address[] public adminList;
    address[] public userList;

    enum Role{
        NONE, 
        USER,
        ADMIN,
        OWNER
    }
        struct UserInfo{
        Role role;
        uint256 registeredAt;
        uint256 lastActive;
        uint256 totalWithdrawn;
        uint256 withdrawalCount;
        bool isActive;
    }

    struct TierLimits{
        uint256 maxDailyWithdrawal;
        uint256 maxSingleWithdrawal;
        uint256 maxTotalWithdrawal;
        uint256 cooldownPeriod;
    }

    struct WithdrawalRecord{
        address user;
        uint256 amount;
        uint256 timestamp;
        bool success;
        string withdrawalType; 
    }
    WithdrawalRecord[] public withdrawalHistory;

    // event 
    event RoleAssigned(address indexed user, Role indexed newRole,address indexed assignedBy);
    event RoleRevoked(address indexed user, Role indexed oldRole, address indexed revokedBy);
    event TierLimitUpdated(Role indexed role, string limitType, uint256 newValue);
    event UserActivated(address indexed user, address indexed activatedBy);
    event UserDeactivated(address indexed user, address indexed deactivatedBy);
    event DailyWithdrawalChecked(address indexed user, uint256 amount, uint256 dailyTotal);
    event TreasureAdded(uint256 amount);
    event WithdrawalApproved(address indexed recipient, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event WithdrawalInitiated(address indexed user, uint256 amount, uint256 timestamp);
    event WithdrawalCompleted(address indexed user, uint256 amount, uint256 timestamp);
    event WithdrawalFailed(address indexed user, uint256 amount, string reason, uint256 timestamp);
    event WithdrawalApprovalUsed(address indexed user, uint256 amount, uint256 remainingAllowance);
    event WithdrawalDetails(
        address indexed user,
        uint256 amount,
        uint256 timestamp,
        string withdrawalType,      // "owner","approved","partial","admin"
        uint256 newTreasureAmount,
        uint256 newAllowance
    )

    // custom errors 
    error Unauthorized(address user, Role required);
    error TierLimitExceeded(string limitType, uint256 limit, uint256 attempted);
    error UserNotActive(address user);
    error CooldownActive(uint256 remainingTime);
    error InvalidRole(Role role);
    error AlreadyHasRole(address user, Role role);
    error NotApproved();
    error InsufficientAllowance(uint256 requested, uint256 available);
    error InsufficientTreasure(uint256 requested, uint256 available);

    // constructor 
    constructor(){
        owner = msg.sender;
        admins[msg.sender] = true;

        tierLimits[Role.OWNER] = TierLimits({
            maxDailyWithdrawal: 1000 ether,
            maxSingleWithdrawal: 500 ether,
            maxTotalWithdrawal: 10000 ether,
            cooldownPeriod: 0
        });
        tierLimits[Role.ADMIN] = TierLimits({
            maxDailyWithdrawal: 100 ether,
            maxSingleWithdrawal: 50 ether,
            maxTotalWithdrawal: 1000 ether,
            cooldownPeriod: 1 hours
        });
        tierLimits[Role.USER] = TierLimits({
            maxDailyWithdrawal: 10 ether,
            maxSingleWithdrawal: 5 ether,
            maxTotalWithdrawal: 100 ether,
            cooldownPeriod: 6 hours
        });

        _assignRole(msg.sender, Role.OWNER);
    }

    // modifier 
    modifier onlyOwner(){
        require(msg.sender == owner, "Access denied");
        _;
    }
    modifier onlyAdmin(){
        require(admins[msg.sender], "Not an admin");
        _;
    }
    modifier onlyAdminOrOwner(){
        if(msg.sender != owner && !admins[msg.sender] && userInfo[msg.sender].role != Role.ADMIN){
            revert Unauthorized(msg.sender, Role.ADMIN)
        }
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
    modifier onlyActiveUser(){
        if(!userInfo[msg.sender].isActive) revert UserNotActive(msg.sender);
        if(userInfo[msg.sender].role == Role.NONE) revert Unauthorized(msg.sender, Role.USER);
        _;
    }
    modifier checkTierLimits(uint256 amount){
        Role userRole = userInfo[msg.sender].role;
        TierLimits memory limits = tierLimits[userRole];

        // check single withdrawal limit 
        if(amount > limits.maxSingleWithdrawal){
            revert TierLimitExceeded("maxSingleWithdrawal",limits.maxSingleWithdrawal, amount);
        }

        // check daily limit 
        uint256 today = block.timestamp / 1 days; 
        uint256 newDailyTotal = dailyWithdrawn[msg.sender][today] + amount;
        if(newDailyTotal > limits.maxDailyWithdrawal){
            revert TierLimitExceeded("maxTotalWithdrawal", limits.maxDailyWithdrawal, newDailyTotal);
        }

        //check total withdrawal limit
        uint256 newTotal =userInfo[msg.sender].totalWithdrawn + amount;
        if(newTotal > limits.maxTotalWithdrawal){
            revert TierLimitExceeded("maxTotalWithdrawal",limits.maxTotalWithdrawal, newTotal);
        }

        // check cooldown 
        if(block.timestamp - lastWithdrawalTime[msg.sender] < limits.cooldownPeriod){
           uint256 remaining = limits.cooldownPeriod - (block.timestamp - lastWithdrawalTime[msg.sender]);
           revert CooldownActive(remaining);
        }

        _;
    }

    
    // role management functions + internal func to do them 
    function assignRole(address user, Role role) public onlyOwner{
        if(role == role.NONE) revert InvalidRole(role);
        if(userInfo[user].role == role) revert AlreadyHasRole(user, role);

        Role oldRole = userInfo[user].role;
        _removeFromRoleList(user, oldRole);
        _assignRole(user, role);

        emit RoleAssigned(user, role, msg.sender);
        if(oldRole != role.NONE){
            emit RoleRevoked(user, oldRole, msg.sender);
        }
    }

    function _assignRole(address user, Role role) internal {
        userInfo[user] = UserInfo({
            role : role,
            registeredAt: block.timestamp,
            lastActive: block.timestamp,
            totalWithdrawn: 0,
            withdrawalCount: 0,
            isActive: true
        });

        if(role == Role.OWNER){
            ownerList.push(user);
            admins[user] = true;
        } else if(role == Role.ADMIN){
            adminList.push(user);
            admins[user] = true;
        } else if( role == Role.USER){
            userList.push(user);
        }
    }

    function _removeFromRoleList(address user, Role role) internal{
        if(role == Role.OWNER){
            _removeFromArray(ownerList, user);
            owners[user] = false;
        } else if(role = Role.ADMIN){
           _removeFromArray(adminList, user);
           admins[user] =false;
        } else if(role == Role.USER){
            _removeFromArray(userList, user);
        }
    }

    function _removeFromArray(address[] storage arr, address user) internal{
        for(uint256 i=0; i<arr.length; i++){
            if(arr[i] == user){
                arr[i] = arr[arr.length -1];
                arr.pop();
                break;
            }
        }
    }

    function revokeRole(address user) public onlyOwner{
        Role oldRole = userInfo[user].role;
        if(oldRole == Role.NONE) revert InvalidRole(oldRole);

        _removeFromRoleList(user, oldRole);
        delete userInfo[user];

        emit RoleRevoked(user, oldRole, msg.sender);
    }

    function activateUser(address user) public onlyAdmin{
        require(userInfo[user].role != Role.NONE, "User doesn't exist");
        userInfo[user].isActive = true;
        emit UserActivated(user, msg.sender);
    }

    function deactivateUser(address user) public onlyAdmin{
        require(user != owner, "Cannot deactivate owner");
        require(userInfo[user].role != Role.NONE, "User doesn't exist");
        userInfo[user].isActive = false;
        emit UserActivated(user, msg.sender);
    }


    // tier limit management functions 
    function updateTierLimitMaxDaily(Role role, uint256 newLimit) public onlyOwner{
        tierLimits[role].maxDailyWithdrawal = newLimit;
        emit TierLimitUpdated(role, "maxDailyWithdrawal", newLimit);
    }
    function updateTierLimitMaxSingle(Role role, uint256 newLimit) public onlyOwner{
        tierLimits[role].maxSingleWithdrawal = newLimit;
        emit TierLimitUpdated(role, "maxSingleWithdrawal", newLimit);
    }
    function updateTierLimitMaxTotal(Role role, uint256 newLimit) public onlyOwner{
        tierLimits[role].maxTotalWithdrawal = newLimit;
        emit TierLimitUpdated(role, "maxTotalWithdrawal", newLimit);
    }
    function updateTierLimitCooldown(Role role, uint256 newLimit) public onlyOwner{
        tierLimits[role].cooldownPeriod = newCooldown;
        emit TierLimitUpdated(role, "cooldownPeriod", newCooldown);
    }


    // treasure functions 
    function addTreasure() public payable onlyAdminOrOwner{
        require(msg.value >0, "Must be more than 0");
        treasureAmount += msg.value;
    }

    receive() external payable{
        treasureAmount += msg.value;
        emit TreasureAdded(msg.value);
    }

    fallback() external payable{
        treasureAmount+= msg.value;
        emit TreasureAdded(msg.value);
    }


    // withDrawal management functions
    function approveWithdrawal(address recipient, uint256 amount) public onlyAdminOrOwner{
        require(amount <= treasureAmount,"Not enough treasure");
        withdrawalAllowance[recipient] = amount;
        emit WithdrawalApproved(recipient, amount);
    }

    function renounceOwnership() public onlyOwner{
        owner = address(0);
        admins[address(0)] = false;
    }

    function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function withdrawTreasure(uint256 amount) public onlyActiveUser checkTierLimits(amount){
        uint256 timestamp = block.timestamp;
        uint256 today = block.timestamp / 1 days;
        string memory withdrawalType;
        Role userRole = userInfo[msg.sender].role;
        bool success = false;


        emit WithdrawalInitiated(msg.sender, amount, timestamp);

        if(msg.sender == owner || userRole == Role.OWNER){
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
            withdrawalAllowance[msg.sender] -= amount;
            treasureAmount -= amount;

            userInfo[msg.sender].totalWithdrawn += amount;
            userInfo[msg.sender].withdrawalCount++;
            userInfo[msg.sender].lastActive = block.timestamp;
            dailyWithdrawn[msg.sender][today] += amount;
            lastWithdrawalTime[msg.sender] = block.timestamp;

            (bool success, ) =msg.sender.call{value: amount}("");
            require(success, "transaction failed");
    
            emit WithdrawalCompleted(msg.sender, amount, timestamp);
            emit WithdrawalApprovalUsed(msg.sender, amount, withdrawalAllowance[msg.sender])
            emit WithdrawalDetails(msg.sender, amount, timestamp, withdrawalType,
            treasureAmount, withdrawalAllowance[msg.sender]);
            emit DailyWithdrawalChecked(msg.sender, amount, dailyWithdrawn[msg.sender][today]);
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

    function getUserRole(address user) public view returns(Role){
        return userInfo[user].role;
    }

    function getUserInfo(address user) public view returns(UserInfo memory){
        return userInfo[user];
    }

    function getRemainingDailyAllowance(address user) public view returns(uint256){
        uint256 today = block.timestamp / 1 days;
        Role = userRole = userInfo[user].role;
        uint256 dailyLimit = tierLimits[userRole].maxDailyWithdrawal;
        uint256 withdrawnToday = dailyWithdrawn[user][today];

        if(withdrawanToday >= dailyLimit){
            return 0;
        }
        return dailyLimit - withdrawanToday;
    }

    function getRemainingCooldown(address user) public view returns(uint256){
        uint256 today = block.timestamp / 1 days;
        Role = userRole = userInfo[user].role;
        uint256 cooldown = tierLimits[userRole].cooldownPeriod;
        uint256 timeSinceLastWithdrawal = block.timestamp - lastWithdrawalTime[user];

        if(timeSinceLastWithdrawal >= cooldown){
            return 0;
        }
        return cooldown - timeSinceLastWithdrawal;
    }

    function getAllOwners() public view returns (address[] memory) {
        return ownerList;
    }
    
    function getAllAdmins() public view returns (address[] memory) {
        return adminList;
    }
    
    function getAllUsers() public view returns (address[] memory) {
        return userList;
    }
    
    function getRoleCounts() public view returns(uint256 owners, uint256 admins, uint256 users){
         return (ownerList.length, adminList.length, usersList.length);
    } 

    function getRecentWithdrawals(uint256 count) public view returns(WithdrawalRecord[] memory){
        if(count > withdrawalHistory.length){
            count = withdrawalHistory.length;
        }

        WithdrawalRecord[] memory recent = new WithdrawalRecord[](count);
        for(uint256 i=0; i<count; i++){
            recent[i]= withdrawalHistory[withdrawalHistory.length, "Invalid Index"];
        }
        return recent;
    }

    function getWithdrawalByIndex(uint256 index) public view returns (WithdrawalRecord memory){
        require(index < withdrawalHistory.length, "Invalid Index");
        return withdrawalHistory[index];
    }

     // total amount withdrawn by user
    function getTotalWithdrawnByUser(address user) public view returns(uint256){
      uint256 total =0;
      uint256[] storage indices = userWithdrawalIndices[user];

      for(uint256 i=0; i, indices.length; i++){
        if(withdrawalHistory[indices[i]].success){
            total += withdrawalHistory[indices[i]].amount;
        }
      }
      return total
    }

    function getWithdrawalsInTimeRange(uint256 startTime, uint256 endTime) public view returns(WithdrawalRecord[] memory){
        uint256 count =0;

        for(uint256 i=0; i<withdrawalHistory.length; i++){
            if(withdrawalHistory[i].timestamp >= startTime && withdrawalHistory[i].timestamp <= endTime){
                count++;
            }
        }

        WithdrawalRecord[] memory filtered= new WithdrawalRecord[](count);
        uint256 index =0;

        for(uint256 i=0; i<withdrawalHistory.length; i++){
            if(withdrawalHistory[i].timestamp >= startTime &&  withdrawalHistory[i].timestamp <= endTime){
                filtered[index] = withdrawalHistory[i];
                index++;
            }
        }
        return filtered;
    }

    function checkMyAllowance() public view onlyApproved returns (uint256) {
       return withdrawalAllowance[msg.sender];
    } 

    function trasferOwnership(address newOwner) public onlyOwner{
        require(newOwner != address(0), "New Owner cannot be 0 address");
        owner = newOwner;
    }

    // addAdmin and removeAdmin function as now useless as we have assign role now 
    // userInfo maintains all roles as we can differentiate on basis of role 
    function addAdmin(address admin) public onlyOwner{
        admins[admin] = true;
    }
    function removeAdmin(address admin) public onlyAdmin{
        require(admin != owner, "Cannot remove owner as admin");
        admins[admin] = false;
    }

    //additional events 
    event AdminAdded(address indexed admin);
    event AdminRemoved(address indexed admin);
    event OwnershipRenounced(address indexed previousOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
}

contract WithdrawalHistoryIndexer{
    mapping(address => uint256[]) public userWithdrawalTimestamps;

    function indexWithrawal(address user, uint256 timestamp) external{
        userWithdrawalTimestamps[user].push(timestamp);
    }
}





// dailyWithdrawn[0x123][20250603] = 5 ether;  address + day number  = ether 
// event => emit 
// internal function (direct usage)
// error => revert
// multiple internal functions - revokeRole => _removeFromRoleList => _removeFromArray