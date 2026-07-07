pragma solidity ^0.8.0;

import "./Day14-BaseDepositBox.sol";

contract BasicDepositBox is BaseDepositBox{
    function getBoxType() external pure override returns(string memory){
      return "Basic";
    }
}

contract PremiumDepositBox is BaseDepositBox{
    mapping(string => string) public metadata;

    function setMetaData(string memory key, string memory value) external onlyOwner{
        metadata[key] = value; 
    }

    function getBoxType() external pure override returns(string memory){
      return "Premium";
    }
}

contract TimeLockDepositBox is BaseDepositBox{
    uint256 public unlockTime;

    constructor(uint256 _lockDuration){
        unlockTime = block.timestamp + _lockDuration;
    }

    modifier timeUnlocked(){
        require(block.timestamp >= unlockTime, "Still locked");
        _;
    }

    function getSecret() public view override timeUnlocked returns(string memory){
        return super.getSecret();
    }

    function getBoxType() external pure override returns(string memory){
        return "TimeLocked";
    }
}

contract MultiSigDepositBox is BaseDepositBox{
    address[] public owners;
    mapping(address => bool) public isOwner;
    uint256 public requiredApprovals;

    mapping(address => mapping(uint256 => bool)) hasApproved;

    struct Request{
        address requester;
        string secret;
        bool executed;
        uint256 timestamp;
    }
    mapping(uint256 => Request) public requests;
    uint256 public requestCounter;

    modifier onlyOwners() {
        require(isOwner[msg.sender], "Not an owner");
        _;
    }
     modifier validRequest(uint256 requestId) {
        require(requestId > 0 && requestId <= requestCounter, "Invalid request");
        _;
    }
    modifier notExecuted(uint256 requestId) {
        require(!requests[requestId].executed, "Request already executed");
        _;
    }
    modifier notApprovedByCaller(uint256 requestId) {
        require(!hasApproved[msg.sender][requestId], "Already approved");
        _;
    }
    
    constructor(address[] memory _owners, uint256 _requiredApprovals){
        require(_owners.length >0, "Atleast one owner required");
        require(_requiredApprovals>0,"cannot be 0");
        require(_requiredApprovals <= _owners.length, "Required approvals too high");

        for(uint256 i=0; i< _owners.length; i++){
           require(_owners[i] != address(0), "Invalid owner address");
           require(!isOwner[owner[i]],"Duplicate Owner");
           isOwner[owner[i]] = true;
           owners.push(owner[i]);
        }
        requiredApprovals = _requiredApprovals;
        address deployer = msg.sender;
        if(!isOwner[deployer]){
            isOwner[deployer] = true;
            owners.push(deployer);
        }
    }

    function storeSecret(string calldata _secret) external override onlyOwners{
       requestCounter++;
       requests[requestCounter] = Request({
        requester: msg.sender,
        secret: _secret,
        executed: false,
        timestamp: block.timestamp
       });
       hasApproved[msg.sender][requestCounter] = true;
       approvalsCount[requestCounter] =1;
    }

    function approveRequest(uint256 requestId) external 
        onlyOwners 
        validRequest(requestId)
        notExecuted(requestId)
        notApprovedByCaller(requestId)
    {
        hasApproved[msg.sender][requestId] = true;
        approvalCount[requestId]++;
        
        emit ApprovalAdded(requestId, msg.sender);
        
        // Check if we have enough approvals
        if (approvalCount[requestId] >= requiredApprovals) {
            isApproved[requestId] = true;
        }
    }

    function executeRequest(uint256 requestId) external 
        onlyOwners 
        validRequest(requestId)
        notExecuted(requestId)
    {
        require(isApproved[requestId], "Not enough approvals");
        
        Request storage request = requests[requestId];
        request.executed = true;
        
        // Store the secret in the base contract
        super.storeSecret(request.secret);
        
        emit RequestExecuted(requestId, msg.sender);
    }

    // Cancel a request (only the requester can cancel)
    function cancelRequest(uint256 requestId) external 
        validRequest(requestId)
        notExecuted(requestId)
    {
        require(msg.sender == requests[requestId].requester, "Not requester");
        
        requests[requestId].executed = true; // Mark as executed to prevent further actions
        emit RequestCancelled(requestId, msg.sender);
    }

    // Get request details
    function getRequestDetails(uint256 requestId) external view 
        validRequest(requestId) 
        returns (
            address requester,
            bool executed,
            uint256 approvals,
            bool approved,
            uint256 timestamp
        )
    {
        Request storage request = requests[requestId];
        return (
            request.requester,
            request.executed,
            approvalCount[requestId],
            isApproved[requestId],
            request.timestamp
        );
    }

    // Get pending requests (not executed)
    function getPendingRequests() external view returns (uint256[] memory) {
        uint256 pendingCount = 0;
        // First count pending requests
        for (uint256 i = 1; i <= requestCounter; i++) {
            if (!requests[i].executed) {
                pendingCount++;
            }
        }
        // Then collect them
        uint256[] memory pendingRequests = new uint256[](pendingCount);
        uint256 index = 0;
        for (uint256 i = 1; i <= requestCounter; i++) {
            if (!requests[i].executed) {
                pendingRequests[index] = i;
                index++;
            }
        } 
        return pendingRequests;
    }

    function getBoxType() external pure override returns (string memory) {
        return "MultiSig";
    }
}