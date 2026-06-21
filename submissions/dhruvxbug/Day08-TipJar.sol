pragma solidity ^0.8.30;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract TipJar{
    AggregatorV3Interface internal dataFeed;

    address public owner;
    mapping(string => uint256) public conversionRates;
    string[] public supportedCurrencies;
    uint256 public totalTipsRecieved;
    mapping(address => uint256) public tipperContributions;
    mapping(string => uint256) public tipsPerCurrency;

    // price chainlink 
    mapping(string => AggregatorV3Interface) public priceFeeds;
    mapping(string => uint8) public priceFeedDecimals;

    //leaderboard 
    address[] public topTippers;
    mapping (address => uint256) public totalTipsGiven;
    uint256 public leaderboardUpdateThreshold = 1 ether;

    struct TipGoal {
        string name;
        uint256 targetAmount,
        uint256 currentAmount;
        bool isActive;
        address creator;
        uint256 createdAt;
        uint256 deadline;
    }
    mapping(uint256 => TipGoal) public tipGoals;
    uint256 public goalCount;
    mapping(uint256 => mapping(address => uint256)) public goalContributions;

    struct RecurringTip{
        address recipient;
        uint256 amount;
        uint256 frequency;
        uint256 lastPaid;
        uint256 nextPayment;
        bool isActive;
        uint256 totalPaid;
    }
    mapping(address => RecurringTip[]) public subscriptions;
    uint256 public subscriptionCounter;


    event TipReceived(address indexed tipper, string currency, uint256 amount, uint256 ethValue);
    event GoalCreated(uint256 indexed goalId, string name, uint256 targetAmount, uint256 deadline);
    event GoalContributed(uint256 indexed goalId, address indexed contributor, uint256 amount);
    event GoalCompleted(uint256 indexed goalId, string name);
    event SubscriptionCreated(address indexed subscriber, address indexed recipient, uint256 amount, uint256 frequency);
    event SubscriptionCancelled(address indexed subscriber, uint256 subscriptionId);
    event RecurringTipProcessed(address indexed subscriber, address indexed recipient, uint256 amount);

    modifier onlyOwner() {
    require(msg.sender == owner, "Only owner can perform this action");
    _;
    }
 
    constructor() {
     owner = msg.sender;

     addPriceFeed("ETHUSD", 0x694AA1769357215DE4FAC081bf1f309aDC325306, 8);
     addPriceFeed("BTCUSD", 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43, 8);
    }

    // ============ PRICE FEED FUNCTIONS ============

    // only adding curreny name and testnet addresses with decimals 
    function addPriceFeed(string memory _currency, address _feedAddress, uint8 _decimals) public onlyOwner{
      priceFeeds[_currency] = AggregatorV3Interface(_feedAddress);
      priceFeedDecimals[_currency] = _decimals;
      addCurrency(_currency, 0);
    }

    // getting the current price using the address and chainlink .lastestRoundData() function
    // call this always to get the latest price of the token / address
    function getChainlinkDataFeedLatestPrice(string memory _currency) public view returns (int256) {
     require(address(priceFeeds[_currency]) != address(0), "Price feed not set");
    ( /* uint80 roundId */
      ,int256 price
      ,/*uint256 startedAt*/
      ,/*uint256 updatedAt*/
      ,/*uint80 answeredInRound*/
    ) = _currency.latestRoundData();
    require(price >0, "Invalid price");
    uint8 feedDecimals = priceFeedDecimals[_currency];
      return uint256(price) * (10**feedDecimals); // decimals to convert to more readble format 
    }
    
    // actual conversion ,return directly if ETH ,or else call getChainLinkDataFeedLatestPrice
    function convertToETH(string memory _currency, uint256 _amount) public view returns (uint256){
        if(keccak256(bytes(_currency)) == keccak256(bytes("ETH"))){
            return _amount;
        }

        uint256 price = getChainlinkDataFeedLatestPrice(_currency);
        return (_amount * 10**18) / price;
    }

    function addCurrency(string memory _currency) public onlyOwner{
        bool currencyExists = false;
        for(uint i=0; i< supportedCurrencies.length; i++){
            if(keccak256(bytes(supportedCurrencies[i])) == keccak256(bytes(_currency))){
                currencyExists = true;
                break;
            }
        }

        if(!currencyExists){
            supportedCurrencies.push[_currency];
        }
        conversionRates[_currency] = _rateToETH;
    }

    function convertToETH(string memeory _currencyCode, uint256 _amount) public view returns(uint256){
        require(conversionRates[_currencyCode]>0, "Currency not supported");

        uint256 ethAmount = _amount * conversionRates[_currencyCode];
        return ethAmount;
    }

     // ============ MULTI-CURRENCY TIPPING ============

    function tipInETH() public payable{
        require(msg.value>0,"Amount needs to be more than 0");

        tipperContributions[msg.sender] += msg.value;
        totalTipsRecieved += msg.value;
        tipsPerCurrency["ETH"] += msg.value;
        totalTipsGiven[msg.sender] += msg.value;

        updateLeaderboard(msg.sender);
        emit TipReceived(msg.sender, "ETH", msg.value, msg.value);
    }

    function tipInCurrency(string memeory _currency, uint256 amount) public payable{
        require(keccak256(bytes(_currency)) != keccak256(bytes("ETH")), "Use tipInETH function");
        require(amount>0,"Amount needs to be more than 0");
        
        uint256 ethAmount = convertToETH(_currencyCode, amount);
        require(msg.value == ethAmount, "Amount does not match");

        tipperContributions[msg.sender] += msg.value;
        totalTipsRecieved += msg.value;
        tipsPerCurrency[_currencyCode] += amount;
        totalTipsGiven[msg.sender] += msg.value;

        updateLeaderboard(msg.sender);
        emit TipReceived(msg.sender, _currency, _amount, msg.value);
    }

    function withdrawTips() public onlyOwner{
        uint256 contractBalance = address(this).balance;
        require(contractBalance>0,"contract balance is 0");

        (bool success, ) = msg.sender.call{value: contractBalance}("");
        require(success, "Transfer failed");

        totalTipsRecieved = 0;
    }

    // ============ TIPPING GOALS ============

    function createTipGoal(
        string memory _name, 
        uint256 _targetAmount, 
        uint256 _durationInDay
    ) public onlyOwner{
        require(_targetAmount >0, "Target must be >0");
        
       tipGoals[goalCount] = TipGoal({
        name: _name,
        targetAmount: _targetAmount,
        currentAmount: 0,
        isActive: true,
        creator: msg.sender,
        createdAt: block.timestamp,
        deadline: block.timestamp + (_durationInDays * 1 days)
       });

       emit GoalCreated(goalCount, _name, _targetAmount, block.timestamp + (_durationInDay * 1 days));
       goalCount++;
    }

    function contributeToGoal(uint256 _goalId) public payable{
        require(_goalId < goalCount, "Goal does not exist");
        require(tipGoals[_goalId].isActive , "Goal is not active");
        require(block.timestamp <= tipGoals[_goalId].deadline, "Goal deadline passed");
        require(msg.value > 0, "Contribution must be > 0");

       tipsGoal[_goalId].currentAmount += msg.value;
       goalContributions[_goalId][msg.sender] += msg.value;

       tipperContributions[msg.sender] += msg.value;
       totalTipsReceived += msg.value;
       totalTipsGiven[msg.sender] += msg.value;

       updateLeaderboard(msg.sender);
       emit GoalContributed(_goalId, msg.sender, msg.value);

       if(tipGoals[_goalId].targetAmount <= tipGoals[_goalId].targetAmount){
        tipGoals[_goalId].isActive = false;
        emit GoalCompleted(_goalId, tipGoals[_goalId].name);
       }
    }

    function getGoalProgress(uint256 _goaldId) public view returns(uint256 percentage, uint256 remaining){
        require(_goaldId < goalCount, "Goal does not exist");
        TipGoal memory goal = tipGoals[_goaldId];
        percentage = (goal.currentAmount * 100) / goal.targetAmount;
        remaining = goal.targetAmount - goal.currentAmount;
        return (percentage, remaining);
    }

    function withdrawGoalFunds(uint256 _goalId) public onlyOwner{
        require(_goaldId < goalCount, "Goal does not exist");
        require(!tipGoals[_goalId].isActive, "Goal still active");
        require(tipGoals[_goalId].currentAmount >0, "No funds to withdraw");

        uint256 amount = tipGoals[_goalId].currentAmount;
        tipsGoals[_goalId].currentAmount =0;

        (bool success, ) = payable(owner).call{value: amount}("");
        require(success, "Transfer failed");
    }

    // ============ LEADERBOARD ============

    function updateLeaderboard(address _tipper) internal{
        uint256 totalGiven = totalTipsGiven[_tipper];

        if(totalGiven < leaderboardUpdateThreshold) return;

        bool exists = false;
        // break if the _tipper already exists in the leaderboard 
        for(uint i=0; i< topTippers.length; i++){
            if(topTippers[i] == _tipper){
                exists = true;
                break;
            }
        }

        // so we are adding the caller anyways and sorting the leaderboard later
        // to only store the top 50
        if(!exists){
            topTippers.push(_tipper);
        }

        for(uint i =0; i <topTippers.length; i++){
            for(uint j = i+1; j < topTippers.length; j++){
                if(totalTipsGiven[topTippers[i]] < totalTipsGiven[topTippers[j]]){
                    (topTippers[i], topTippers[j]) = (topTippers[j], topTippers[i]);
                }
            }
        }

        while (topTippers.length > 50){
            topTippers.pop();
        }
    }

    function getLeaderboard(uint256 _count) public view returns(address[] memory, uint256[] memory){
        uint256 resultCount = _count > topTippers.length ? topTippers.length : _count;
        address[] memory addresses = new address[](resultCount);
        address[] memory amounts = new uint256[](resultCount);

        // topTippers consists of uint256 (position) and addresses 
        // so we will need totalTipsGiven for amount
        for(uint i =0; i< resultCount; i++){
            addresses[i] = topTippers[i];
            amounts[i] = totalTipsGiven[topTippers[i]];
        }

        return(addresses, amounts);
    }

    function setLeaderboardThreshold(uint256 _threshold) public onlyOwner{
       leaderboardUpdateThreshold = _threshold;
    }

    // ============ RECURRING TIPS (SUBSCRIPTIONS) ============

    function createSubscription(address _recipient, uint256 _amount, uint256 _frequencyInDays) public payable{
        require(_recipient != address(0), "Invalid recipient");
        require(_amount > 0,"Amount cannot be 0");
        require(_frequencyInDays > 0, "Frequency must be > 0");
        require(msg.value >= _amount, "Insufficient initial payment");

        uint256 frequencyInSeconds = _frequencyInDays * 1 days;

        RecurringTip memory newSubscription = RecurringTip({
            recipient: _recipient,
            amount: _amount,
            frequency: frequencyInSeconds,
            lastPaid: block.timestamp,
            nextPayment: frequencyInSeconds + block.timestamp,
            isActive: true,
            totalPaid: _amount
        });

        subscriptions[msg.sender].push(newSubscription);

        (bool success, ) = payable(_recipient).call{value: _amount}("");
        require(success, "Payment failed");

        if(msg.value > _amount){
            (bool refundSuccess, ) = payable(msg.sender).call{value: msg.value - _amount}("");
            require(refundSuccess," Refund Failed");
        }

        emit SubscriptionCreated(msg.sender, _recipient, _amount, _frequencyInDays);
        subscriptionCounter++;
    }

    function processRecurringTips() public{
      for(uint i =0; i < subscriptions[msg.sender].length; i++){
        RecurringTip storage sub = subscriptions[msg.sender][i];

        if(sub.isActive && block.timestamp >= sub.nextPayment){
            uint256 paymentsDue = (block.timestamp - sub.lastPaid) / sub.frequency;

            if(paymentsDue >0){
                uint256 totalAmount = sub.amount * paymentsDue;

                if(address(this).balance >= totalAmount){
                    (bool success, ) = payable(sub.recipient).call{value: totalAmount}("");
                    if(success){
                        sub.lastPaid = block.timestamp;
                        sub.nextPayment = block.timestamp + sub.frequency;
                        sub.totalPaid += totalAmount;

                        emit RecurringTipProcessed(msg.sender, sub.recipient, totalAmount);
                    }
                }
            }
        }
      }  
    }

    function cancelSubscription(uint256 _subscriptionId) public {
        require(_subscriptionId < subscriptions[msg.sender].length, "Subscription does not exist");
        require(subscriptions[msg.sender][_subscriptionId].isActive, "Subscription not active anymore");
        
        subscriptions[msg.sender][_subscriptionId].isActive = false;

        emit SubscriptionCancelled(msg.sender, _subscriptionId);
    }

    function getSubscriptions(address _subscriber) public payable returns(RecurringTip){
      return(subscriptions[_subscriber]);   
    }

    function addFundsToSubscription() public payable{
        require(msg.value >0,"Amount needs to be positive");
    }

    // ===== old funcstions 

    function getSupportedCurrencies() public view returns (string[] memory) {
    return supportedCurrencies;
    }
    
    function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }
    
    function getTipperContribution(address _tipper) public view returns (uint256) {
        return tipperContributions[_tipper];
    }
    
    function getTipsInCurrency(string memory _currencyCode) public view returns (uint256) {
        return tipsPerCurrency[_currencyCode];
    }
    
    function getConversionRate(string memory _currencyCode) public view returns (uint256) {
        require(conversionRates[_currencyCode] > 0, "Currency not supported");
        return conversionRates[_currencyCode];
    }
}



// addPriceFeed(onlyOnwer) => added priceFeeds + decimal => getChainlinkDataFeedLatestPrice
// addPriceFeed(onlyOnwer) => addCurrency 