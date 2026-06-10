pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract sendSomeTokens is Ownable{
    using SafeERC20 for IERC20;
    using SafeMath for uint256; 

   address public owner;
   //friend list
   mapping(address => bool) public registeredFriends;
   address[] public friendList;

   mapping(address => uint256) public balances;
   // Debts: debtor => creditor => tokenAddress => debt details
   mapping(address => mapping(address => mapping(address => Debt))) public debts;
   // tokenAddress => user => balance
   mapping(address => mapping(address => uint256)) public erc20Balances;
   mapping(address => PaymentRecord[]) public paymentHistory;
   mapping(uint256 => Dispute) public disputes;
   uint256 public disputeCounter;

   uint256 public defaultInterestRate = 500;
   uint256 public interestAccrualInterval = 30 days;

   mapping(uint256 => ForgivenessRequest) public forgivenessRequests;
   uint256 public forgivenessCounter;

   mapping(address => uint256) public stakedTokens;
   uint256 public minimumStake = 100 ether;

    // events 
    event FriendAdded(address indexed user);
    event Deposited(address indexed user, uint256 amount, address token);
    event DebtRecorded(address indexed debtor, address indexed creditor, uint256 amount, address token, uint256 interestRate, uint256 dueDate);
    event DebtPaid(address indexed debtor, address indexed creditor, uint256 amount, address token, bool late);
    event InterestAccrued(address indexed debtor, address indexed creditor, uint256 interestAmount, address token);
    event DebtForgiven(uint256 indexed requestId, address indexed debtor, address indexed creditor, uint256 amount);
    event DisputeCreated(uint256 indexed disputeId, address indexed plaintiff, address indexed defendant, uint256 amount);
    event DisputeResolved(uint256 indexed disputeId, address indexed winner, address indexed loser);
    event ReputationUpdated(address indexed user, int256 change, uint256 newScore);
    event TokensStaked(address indexed user, uint256 amount);
    event TokensWithdrawn(address indexed user, uint256 amount);
   
    struct Debt{
        uint256 amount;
        uint256 remainingAmount;
        uint256 interestRate;
        uint256 creationTime;
        uint256 dueDate;
        uint256 lastInterestAccrual;
        bool isDisputed;
        address tokenAddress;  // address(0) for native token
        string description;
    }

    struct PaymentRecord{
        address debtor;
        address creditor;
        uint256 amount;
        address tokenAddress;
        uint256 timestamp;
        bool wasLate;
        uint256 interestPaid;
    }

    struct Dispute{
        address plaintiff;
        address defendant;
        uint256 debtId;
        address tokenAddress;
        uint256 amount;
        string reason;
        uint256 createdAt;
        DisputeStatus status;
        address[] jurors;
        mapping(address =>uint256) jurorVotes;
        uint256 plaintiffVotes;
        uint256 defendantVotes;
        address winner;
        string resolution;
    }
    enum DisputeStatus{ Pending, InProgress, Resolved, Rejected}

    struct ForgivenessRequest{
        address debtor;
        address creditor;
        uint256 amount;
        address tokenAddress;
        string reason;
        uint256 requestedAt;
        bool isApproved;
        uint256 approvedAt; 
    }


   constructor() Ownable(msg.sender){
    // owner = msg.sender not required when using Ownable()
    registeredFriends[owner()] = true;
    friendList.push(owner());
    reputationScores[owner()] = 500;
   }

   // maybe not required coz of Ownable()
   modifier onlyOwner(){
    require(msg.sender == owner, "Only owner can perform this action");
    _;
   }
   modifier onlyRegistered(){
    require(registeredFriends[msg.sender], "you are not registered");
    _;
   }
   modifier onlyDebtParticipant(address debtor, address creditor, address tokenAddress){
    require(msg.sender == debtor || msg.sender == creditor, "Not Auth");
    _;
   }

   function addFriend(address user) public onlyOwner{
    require(user != address(0), "user address cannot be 0");
    require(!registeredFriends[user], "Already registered user");

    registeredFriends[user] =true;
    friendList.push(user);
    reputationScores[user] = 500; // Initial reputation
    emit FriendAdded(user);
   }

   function depositIntoWallet() public payable onlyRegistered{
    require(msg.value > 0,"must send eth");
    balances[msg.sender] += msg.value;
    emit Deposited(msg.sender, msg.value, address(0));
   }

   function depositERC20(address tokenAddress, uint256 amount) public onlyRegistered{
    require(tokenAddress != address(0),"Invalid token address");
    require(amount>0, "Amount cannot be 0");

    // ERC20 token logic used 
    IERC20 token = IERC20(tokenAddress);
    uint256 beforeBalance = token.balanceOf(address(this));
    token.safeTransferFrom(msg.sender, address(this), amount);
    uint256 afterBalance = token.balanceOf(address(this));
    uint256 actualAmount = afterBalance.sub(beforeBalance); // openZeppelin SafeMatch library 

    erc20Balances[tokenAddress][msg.sender] += actualAmount;
    emit Deposited(msg.sender, actualAmount, tokenAddress);
   }

   function recordDebt(
    address _debtor, 
    uint256 amount,
    address tokenAddress,
    uint256 dueDate,
    string memory description,
    uint256 customInterestRate
    ) public onlyRegistered {
     require(amount > 0,"amount cannot be 0");
     require(_debtor != address(0), "Invalid address");
     require(registeredFriends[_debtor], "Address not registered");
     require(dueDate > block.timestamp, "Due date must be in future");

     uint256 interestRate = customInterestRate > 0 ? customInterestRate : defaultInterestRate;
     

     debts[_debtor][msg.sender][tokenAddress] = Debt({
        amount: amount,
        remainingAmount: amount,
        interestRate: interestRate,
        creationTime: block.timestamp,
        dueDate: dueDate,
        lastInterestAccrual: block.timestamp,
        isDisputed: false;
        tokenAddress: tokenAddress,
        description: description
     });

     emit DebtRecorded(_debtor, msg.sender, amount, tokenAddress, interestRate, dueDate);
   }

   function _accrueInterest(address debtor, address creditor, address tokenAddress) internal returns(uin256){
      Debt storage debt = debts[debtor][creditor][tokenAddress];
      if (debt.remainingAmount == 0 || debt.lastInterestAccrual == 0) return;

      uint256 timeElapsed = block.timestamp.sub(debt.lastInterestAccrual);
      if (timeElapsed < interestAccrualInterval) return;

      uint256 annualInterest = debt.remainingAmount.mul(debt.interestRate).div(10000);
      uint256 interestAmount = annualInterest.mul(timeElapsed).div(365 days);

      debt.remainingAmount += interestAmount;
      debt.lastInterestAccrual = block.timestamp;

      emit InterestAccrued(debtor, creditor, interestAmount, tokenAddress);
      return interestAmount;
   }

   function payFromWallet(address _creditor, uint256 amount, address tokenAddress) public onlyRegistered{
     require(_creditor != address(0), "Invalid address");
     require(registeredFriends[_creditor], "Address not registered");
     require(amount > 0,"amount cannot be 0");
     require(tokenAddress != address(0),"Invalid token address");

     Debt storage debt = debts[msg.sender][_creditor][tokenAddress];
     require(debt.remainingAmount > 0,"cannot be 0");
     require(!debt.isDisputed,"Debt is disputed");

     _accrueInterest(msg.sender, _creditor, tokenAddress);
     require(debt.remainingAmount >= amount,"Amount exceeds debt");

     bool wasLate = block.timestamp > debt.dueDate;
     uint256 interestPaid = 0;
     uint256 latePenalty = 0;

     if (wasLate) {
            latePenalty = amount.mul(latePaymentPenalty).div(10000);
            amount = amount.add(latePenalty);
     }

     if(tokenAddress == address(0)){
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[_creditor] += amount;
        balances[msg.sender] -= amount;
     } else{
        require(erc20Balances[tokenAddress][msg.sender] >= amount, "Insufficient balance");
        erc20Balances[tokenAddress][_creditor] += amount;
        erc20Balances[tokenAddress][msg.sender] -= amount;
     }

     debt.remainingAmount = debt.remainingAmount - amount;

     paymentHistory[msg.sender].push(PaymentRecord({
            debtor: msg.sender,
            creditor: _creditor,
            amount: amount,
            tokenAddress: tokenAddress,
            timestamp: block.timestamp,
            wasLate: wasLate,
            interestPaid: interestPaid
     }));

     _updateReputation(msg.sender, wasLate, amount);
     emit DebtPaid(msg.sender, _creditor, amount, tokenAddress, wasLate);
   }

   function _updateReputation(address user, bool wasLate, uin256 amountPaid) internal {
     int256 change;
     if(!wasLate){
        change = int256(amountPaid.div(1 ether));
        if (change >50) change =50;
     } else {
        change = -int256(amountPaid.div(2 ether));
        if(change < -30) change =-30;
     }

     uint256 newScore;
     if(change >=0){
        newScore = reputationScores[user] + uint256(change);
     } else{
        if (reputationScores[user] > uint256(-change)) {
                newScore = reputationScores[user] - uint256(-change);
            } else {
                newScore = 0;
            }
     }

     if (newScore > 1000) newScore = 1000;
     reputationScores[user] = newScore;
     emit ReputationUpdated(user, change, newScore);
   }

   function requestDebtForgiveness(
      address creditor,
      uint256 amount,
      address tokenAddress,
      string memory reason
   )public onlyApproved{
     require(creditor != address(0), "Invalid creditor");
     require(registeredFriends[creditor], "Creditor not registered");
     require(amount > 0, "Amount must be > 0");

     Debt storage debt = debts[msg.sender][creditor][tokenAddress];
     require(debt.remainingAmount >= amount, "Amount exceeds remaining debt");

     forgivenessRequests[forgivenessCounter] = ForgivenessRequest({
        debtor: msg.sender,
        creditor: creditor,
        amount: amount,
        tokenAddress: tokenAddress,
        reason: reason,
        requestedAt: block.timestamp,
        isApproved: false,
        approvedAt: 0
     })

     emit DebtForgiven(forgivenessCounter, msg.sender, creditor, amount);
     forgivenessCounter++;
   }

   function approveDebtForgiveness(uint256 requestId) public onlyRegistered{
    ForgivenessRequest storage request = forgivenessRequests[requestId];
    require(request.creditor == msg.sender, "Only creditor can approve");
    require(!request.isApproved, "Already approved");

    Debt storage debt = debts[request.debtor][request.creditor][request.tokenAddress];
    require(debt.remainingAmount >= request.amount, "Debt amount changed");

    debt.remainingAmount -= request.amount;
    request.isApproved = true;
    request.approvedAt = block.timestamp;

    uint256 newScore = reputationScores[msg.sender] + 10;
    if (newScore > 1000) newScore = 1000;
    reputationScores[msg.sender] = newScore;
    
    emit ReputationUpdated(msg.sender, 10, newScore);
   }

   function createDispute(
    address defendant,
    uint256 amount,
    address tokenAddress,
    string memory reason
   )public onlyRegistered{
    require(defendant != address(0), "Invalid defendant");
    require(registeredFriends[defendant], "Defendant not registered");

    require(stakedTokens[msg.sender]>= minimumStake, "Insufficient stake"); 

    disputes[disputeCounter] = Dispute({
            plaintiff: msg.sender,
            defendant: defendant,
            debtId: 0,
            tokenAddress: tokenAddress,
            amount: amount,
            reason: reason,
            createdAt: block.timestamp,
            status: DisputeStatus.Pending,
            jurors: new address[](0),
            plaintiffVotes: 0,
            defendantVotes: 0,
            winner: address(0),
            resolution: ""
        });

    emit DisputeCreated(disputeCounter, msg.sender, defendant, amount);   
    disputeCounter++;
   }

   function staketoken() public payable onlyRegistered{
    require(msg.value > 0, "Must stake something");
    stakedTokens[msg.sender] += msg.value;
    emit TokensStaked(msg.sender, msg.value);
   }

   function unstakeTokens(uint256 amount) public onlyRegistered {
    require(stakedTokens[msg.sender] >= amount, "Insufficient stake");
    require(amount <= stakedTokens[msg.sender] - minimumStake, "Cannot go below minimum stake");
    
    stakedTokens[msg.sender] -= amount;
    payable(msg.sender).transfer(amount);
    emit TokensWithdrawn(msg.sender, amount);
    }

    function resolveDispute(uint256 disputeId, address winner) public onlyOwner{
        Dispute storage dispute = dispute[disputeId];
        require(dispute.status == DisputeStatus.Pending, "Dispute alrerady resolved");
        require(winner == dispute.plaintiff || winner == dispute.defendant, "Invalid winner");

        dispute.status = DisputeStatus.Resolved;
        dispute.winner = winner;
        dispute.resolution = "Resolved by owner";

        uint256 loserStake = stakedTokens[winner == dispute.plaintiff ? dispute.defendant : dispute.plaintiff];
        stakedTokens[winner] += loserStake;
        stakedTokens[winner == dispute.plaintiff ? dispute.defendant : dispute.plaintiff] -= loserStake;
        
        address loser = winner == dispute.plaintiff ? dispute.defendant : dispute.plaintiff;

        updateReputationForDispute(winner, loser);
        emit DisputeResolved(disputeId, winner, winner == dispute.plaintiff ? dispute.defendant : dispute.plaintiff);
    }

    function updfateReputationForDispute(address winner, address loser) internal{
        uint2556 winnerScore = reputationScores[winner] + 20;
        if(winnerScore>1000) reputationScores[winner] =1000;
        emit ReputationUpdated(winner, 20, winnerScore);

        uint256 loserScore = reputationScores[loser] >= 20 ? reputationScores[loser] -20 : 0;
        reputationScores[loser] = loserScore;
        emit ReputationUpdated(loser, -20, loserScore);  
    }

    function getDebtDetails(
        address debtor, 
        address creditor,
        address tokenAddress
    ) public view returns(
        uint256 remaining, 
        uint256 interestRate, 
        uint256 dueDate,
        bool isDisputed,
        string memory description
    ){
        Debt storage debt = debts[debtor][creditor][tokenAddress];
        return(
            debt.remainingAmount,
            debt.interestRate,
            debt.dueDate,
            debt.isDisputed,
            debt.description
        )
    }

    function getPaymentHistory(address user) public view returns(PaymentRecord[] memory){
        return paymentHistory[user];
    }

    function getReputation(address user) public view returns(uint256){
        return reputationScores[user];
    }

    function getDisputeDetails(
        uint256 disputeId
    ) public view returns(
        address plaintiff,
        address defendant,
        uint256 amount,
        string memory reason,
        DisputeStatus status,
        address winner
    ) {
        Dispute storage dispute = disputes[disputeId];
        return (
            dispute.plaintiff,
            dispute.defendant,
            dispute.amount,
            dispute.reason,
            dispute.status,
            dispute.winner
        )
    }

    function checkBalance(address tokenAddress) public view onlyRegistered returns(uint256){
        if(tokenAddress == address(0)){
            return balances[msg.sender];
        } else {
            return erc20Balances[tokenAddress][msg.sender];
        }
    }

    function getTotalDebt(address debtor, address tokenAddress) public view returns(uint256 totalDebt){
        totalDebt =0;
        for(uint i=0; i<friendList.length; i++){
            address creditor = friendList[i];
            totalDebt += debts[debtor][creditor][tokenAddress].remainingAmount;
        }
        return totalDebt;
    }

    function setInterestRate(uin256 newRate) public onlyOwner{
        require(newRate <= 5000,"rate too high");
        defaultInterestRate = newRate;
    }

    function setLatePenalty(uint256 newPenalty) public onlyOwner{
        require(newPenalty <= 1000, "Penalty too high");
        latePaymentPenalty = newPenalty;
    }

    function setMinimumStake(uint256 newStake) public onlyOwner{
        minimumStake = newStake;
    }

    receive() external payable {
        revert("Use depositIntoWallet() instead");
    }

   // .transfer(), no debts involved
   function transferEther(address payable _to, uint256 _amount) public onlyRegistered {
    require(_to != address(0), "Invalid address");
    require(registeredFriends[_to], "Recipient not registered");
    require(balances[msg.sender] >= _amount, "Insufficient balance");

    balances[msg.sender] -= _amount;
    _to.transfer(_amount);
    balances[_to] += _amount;
   }

   function withdraw(uint256 _amount) public onlyRegistered {
    require(balances[msg.sender] >= _amount, "Insufficient balance");

    balances[msg.sender] -= _amount;

    (bool success, ) = payable(msg.sender).call{value: _amount}("");
    require(success, "Withdrawal failed");
   }

   function checkBalance() public view onlyRegistered returns (uint256) {
    return balances[msg.sender];
   }
}