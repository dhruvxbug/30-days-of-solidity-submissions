pragma solidity ^0.8.30;
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract EtherPiggyBank is ReentrancyGuard{
    address public bankManager;
    address[] public members; 
    mapping(address => bool) public registeredMembers;
    mapping(address => uint256) balance;

    mapping(address => uint256) public lastInterestClaimTime;
    mapping(address => uint256) public accuredInterest;
    uint256 public constant ANNUAL_INTEREST_RATE = 5;
    uint256 public constant INTEREST_ACCURAL_PERIOD = 365 days;

    struct GroupGoal{
        uint256 targetAmount;
        uint256 deadline;
        uint256 totalLocked;
        bool active;
        address[] contributors;
        mapping(address => uint256) contributions;
    }
    mapping(uint256 => GroupGoal) public groupGoals;
    uint256 public nextGoalId;

    struct TimeLock{
        uint256 amount;
        uint256 releaseTime;
        bool withdrawn;
    }
    mapping(address => TimeLock[]) public timeLocks;

    mapping(address => uint256) public lastEmergencyWithdrawal;
    uint256 public constant EMERGENCY_PENALTY_PERCENT = 10;
    uint256 public constant EMERGENCY_COOLDOWN = 30 days;

    event InterestClaimed(address indexed user, uint256 amount);
    event GroupGoalCreated(uint256 indexed goalId,uint256 targetAmount, uint256 deadline);
    event GroupGoalContributed(uint256 indexed goalId,address indexed contributor, uint256 amount);
    event GroupGoalReleased(uint256 indexed goalId, uint256 amount);
    event TimeLockCreated(address indexed user, uint256 amount, uint256 releaseTime);
    event EmergencyWithdrawal(address indexed user, uint256 amount, uint256 penalty);
    event InterestAccrued(address indexed user, uint256 amount);


    constructor(){
        bankManager = msg.sender;
        members.push(msg.sender);
        registeredMembers[msg.sender] = true;
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
        lastInterestClaimTime[_member] = block.timestamp;
    }

    function getMembers()public view returns(address[] memory){
        return members;
    }

    function deposit() public payable onlyRegisteredMember{
        require(msg.value > 0, "Invalid amount");
        _claimInterest(msg.sender);
        balance[msg.sender] += msg.value;
    }

    function calculatePendingInterest(address _user) public view returns(uint){
        if(lastInterestClaimTime[_user] == 0 || balance[_user] == 0){
            return 0;
        }

        uint256 timeElapsed = block.timestamp - lastInterestClaimTime[_user];
        uint256 interest = (balance[_user] * ANNUAL_INTEREST_RATE * timeElapsed);

        return interest + accruedInterest[_user];
    }

    function _claimInterest(address _user) internal{
        uint256 pendingInterest = calculatePendingInterest(_user);
        if(pendingInterest > 0){
            balance[_user] += pendingInterest;
            accruedInterest[_user] =0;
            lastInterestClaimTime[_user] = block.timestamp;
            emit InterestClaimed(_user, pendingInterest);
        }
    }

    function claimInterest() public onlyRegisteredMember nonReentrant{
        _claimInterest(msg.sender);
    }

    function createTimeLock(uint256 _amount, uint256 _lockDurationDays) public onlyRegisteredMember nonReentrant{
        require(_amount >0, "Amount must be greater than 0");
        require(_lockDurationDays >=7 && _lockDurationDays <= 1095, "Lock duration must be between 7 and 1095 days");
        require(balance[msg.sender] >= _amount, "Insufficient balance");

        _claimInterest(msg.sender);
        balance[msg.sender] -= amount;

        TimeLock memory newLock = TimeLock({
            amount: _amount;
            releaseTime: block.timestamp + (_lockDurationDays * 1 days),
            withdrawn : false
        });

        timeLocks[msg.sender].push(newLock);
        emit TimeLockCreated(msg.sender, _amount, newLock.releaseTime);
    }

    function withdrawalTimeLock(uint256 _lockIndex) public onlyRegisteredMember nonReentrant{
        require(_lockIndex < timeLocks[msg.sender].length, "Invalid Index");
        TimeLock storage userLock = timeLocks[msg.sender][_lockIndex];
        require(!userLock.withdrawn, "Already withdrawn");
        require(block.timestamp >= userLock.releaseTime, "Wait for lock period to end");

        userLock.withdrawn = true;
        balance[msg.sender] += userLock.amount;

        _claimInterest(msg.sender);
    }

    function getTimeLocks(address _user) public view returns(uint256[] memory amounts, uint256[] memory releaseTime, bool withdrawn){
        uint256 lockCount = timeLocks[_user].length;
        amounts = new uint256[](lockCount);
        releaseTimes = new uint256[](lockCount);
        withdrawn = new bool[](lockCount);

        for(uint i=0; i<lockCount; i++){
            amounts[i] = timeLocks[_user][i].amount;
            releaseTimes[i] = timeLocks[_user][i].releaseTime;
            withdrawn[i] = timeLocks[_user][i].withdraw; 
        }

        return (amounts, releaseTimes, withdrawn);
    }

    function createGroupGoal(uint256 _targetAmount, uint256 _durationDays) public OnlyBankManager{
        require(_targetAmount >0, "TARGET AMOUNT CANNOT BE 0");
        require(_durationDays >= 7 && _durationDays <= 365, "Duration must be between 7 to 365");

        GroupGoal storage newGoal = groupGoals[nextGoalId];
        newGoal.targetAmount = _targetAmount;
        newGoal.deadline = block.timestamp + (_durationDays * 1 days);
        newGoal.active = true;

        emit GroupGoalCreated(nextGoalId, _targetAmount, newGoal.deadline);
        nextGoalId++;
    }

    function contributeToGroupGoal(uint256 _goaldId) public payable onlyRegisteredMember{
        require(_goaldId < nextGoalId, "Invalid goal ID");
        GroupGoal storage goal = groupGoals[_goaldId];
        require(goal.active, "Goal is not active");
        require(block.timestamp <= goal.deadline, "Goal deadline has passed");
        require(msg.value > 0, "Contribution must be greater than 0");
        require(goal.totalLocked + msg.value <= goal.targetAmount, "Contribution would exceed target");

        _claimInterest(msg.sender);
        require(balance[msg.sender] >= msg.value, "Insufficient balance");
        
        balance[msg.sender] -= msg.value;
        goal.totalLocked += msg.value;
        goal.contributions[msg.sender] += msg.value;
        goal.contributors.push(msg.sender);

        emit GroupGoalContributed(_goaldId, msg.sender, msg.value);
        if(goal.totalLocked >= goal.targetAmount){
            _releaseGroupGoal(_goaldId);
        }
    } 

    function _releaseGroupGoal(uint256 goalId) internal{
        require(_goaldId < nextGoalId, "Invalid goal ID");
        GroupGoal storage goal = groupGoals[_goaldId];
        require(goal.active, "Goal already released");
        goal.active = false;

        for(uint i=0; i< goal.contributors.length; i++){
            address contributor = goal.contributors[i];
            uint256 contribution = goal.contributions[contributor];
            if(contribution>0){
                uint256 share = (contribution * goal.totalLocked) / goal.targetAmount; 
                balance[contributor] += share;
            }
        }
        emit GroupGoalReleased(_goaldId, goal.totalLocked);
    }

    function releaseGroupGoal(uint256 _goalId) public OnlyBankManager{
        require(_goaldId < nextGoalId, "Invalid goal ID");
        GroupGoal storage goal = groupGoals[_goaldId];
        require(goal.active, "Goal already released");
        require(block.timestamp > goal.deadline || goal.totalLocked >= goal.targetAmount, "Goal not finished");
        
        _releaseGroupGoal(_goaldId);
    }

    function getGroupGoalInfo(uint256 _goalId) public view returns(
        uint256 targetAmount, 
        uint256 deadline, 
        uint256 totalLocked, 
        bool active,
        address[] memory contributors
    ){
        require(_goalId < nextGoalId, "Invalid goal ID");
        GroupGoal storage goal = groupGoals[_goalId];
        return (goal.targetAmount, goal.deadline, goal.totalLocked, goal.active, goal.contributors);
    }

    function emergencyWithdraw(uint256 _amount) public onlyRegisteredMember nonReentrant{
        require(_amount > 0, "Amount must be greater than 0");
        require(balance[msg.sender] >= _amount, "Insufficient balance");
        require(block.timestamp >= lastEmergencyWithdrawal[msg.sender] + EMERGENCY_COOLDOWN, "Emergency cooldown is active");

        _claimInterest(msg.sender);

        uint256 penalty = (_amount * EMERGENCY_PENALTY_PERCENT) / 100;
        uint256 amountToWithdraw = _amount - penalty;
        
        balance[msg.sender] -= _amount;
        lastEmergencyWithdrawal[msg.sender] = block.timestamp;
        
        // Penalty goes to contract (can be used for future rewards or bank manager)
        (bool success, ) = msg.sender.call{value: amountToWithdraw}("");
        require(success, "Transaction failed");
        
        emit EmergencyWithdrawal(msg.sender, amountToWithdraw, penalty);
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