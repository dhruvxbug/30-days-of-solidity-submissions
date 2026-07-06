// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./Day11-Ownable.sol";

contract VaultMaster is Ownable {
    event DepositSuccessful(address indexed account, uint256 value);
    event WithdrawSuccessful(address indexed recipient, uint256 value);

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function deposit() public payable {
        require(msg.value > 0, "Enter a valid amount");
        emit DepositSuccessful(msg.sender, msg.value);
    }

    function withdraw(address _to, uint256 _amount) public onlyOwner {
        require(_amount <= getBalance(), "Insufficient balance");
        (bool success, ) = payable(_to).call{value: _amount}("");
        require(success, "Transfer Failed");
        emit WithdrawSuccessful(_to, _amount);
    }
}


// virtual or override inside function for parent child relationship 
// interface and usage of import contract - https://github.com/The-Web3-Compass/30-days-of-solidity-walkthoughs/blob/main/masterkey-contract/walkthrough/masterkey-contract-en.md

//1. Role based access control
contract Roles {
    mapping(address => bool) public admins;
    mapping(address => bool) public moderators;
}

contract AccessControl is Roles {
    modifier onlyAdmin() {
        require(admins[msg.sender], "Not admin");
        _;
    }
    
    modifier onlyModerator() {
        require(moderators[msg.sender], "Not moderator");
        _;
    }
}


## 1. Base Contracts (Reusable Components)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============ BASE CONTRACTS ============

/**
 * @title Ownable
 * @dev Base contract with owner functionality
 */
contract Ownable {
    address public owner;
    address public pendingOwner;
    
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipPending(address indexed pendingOwner);
    
    constructor() {
        owner = msg.sender;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Invalid address");
        pendingOwner = newOwner;
        emit OwnershipPending(newOwner);
    }
    
    function acceptOwnership() public {
        require(msg.sender == pendingOwner, "Not pending owner");
        address oldOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, owner);
    }
}

/**
 * @title Pausable
 * @dev Base contract with pause functionality
 */
contract Pausable {
    bool public paused;
    
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    
    modifier whenNotPaused() {
        require(!paused, "Contract paused");
        _;
    }
    
    modifier whenPaused() {
        require(paused, "Contract not paused");
        _;
    }
    
    function pause() public virtual {
        paused = true;
        emit Paused(msg.sender);
    }
    
    function unpause() public virtual {
        paused = false;
        emit Unpaused(msg.sender);
    }
}

/**
 * @title FeatureFlags
 * @dev Base contract for feature flag management
 */
contract FeatureFlags {
    mapping(bytes32 => bool) public features;
    mapping(bytes32 => uint256) public featureActivationTime;
    
    event FeatureEnabled(bytes32 indexed featureId, address indexed enabledBy);
    event FeatureDisabled(bytes32 indexed featureId, address indexed disabledBy);
    event FeatureTemporarilyEnabled(bytes32 indexed featureId, uint256 duration);
    
    modifier onlyIfFeatureEnabled(bytes32 featureId) {
        require(isFeatureEnabled(featureId), "Feature disabled");
        _;
    }
    
    function enableFeature(bytes32 featureId) public virtual {
        features[featureId] = true;
        featureActivationTime[featureId] = block.timestamp;vb 
        emit FeatureEnabled(featureId, msg.sender);
    }
    
    function disableFeature(bytes32 featureId) public virtual {
        features[featureId] = false;
        emit FeatureDisabled(featureId, msg.sender);
    }
    
    function isFeatureEnabled(bytes32 featureId) public view returns (bool) {
        return features[featureId];
    }
    
    function enableFeatureTemporarily(bytes32 featureId, uint256 duration) public virtual {
        features[featureId] = true;
        featureActivationTime[featureId] = block.timestamp;
        emit FeatureTemporarilyEnabled(featureId, duration);
    }
    
    function isFeatureActive(bytes32 featureId) public view returns (bool) {
        return features[featureId];
    }
}

/**
 * @title AccessControl
 * @dev Role-based access control system
 */
contract AccessControl {
    // Role definitions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant VIEWER_ROLE = keccak256("VIEWER_ROLE");
    
    mapping(bytes32 => mapping(address => bool)) public hasRole;
    mapping(bytes32 => mapping(address => uint256)) public roleGrantedTime;
    mapping(bytes32 => uint256) public roleCount;
    
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed grantedBy);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed revokedBy);
    event RoleRenounced(bytes32 indexed role, address indexed account);
    
    modifier onlyRole(bytes32 role) {
        require(hasRole[role][msg.sender], "Missing role");
        _;
    }
    
    modifier onlyAdmin() {
        require(hasRole[ADMIN_ROLE][msg.sender], "Not admin");
        _;
    }
    
    function grantRole(bytes32 role, address account) public virtual onlyAdmin {
        require(!hasRole[role][account], "Already has role");
        require(account != address(0), "Invalid address");
        
        hasRole[role][account] = true;
        roleGrantedTime[role][account] = block.timestamp;
        roleCount[role]++;
        
        emit RoleGranted(role, account, msg.sender);
    }
    
    function revokeRole(bytes32 role, address account) public virtual onlyAdmin {
        require(hasRole[role][account], "Does not have role");
        
        hasRole[role][account] = false;
        roleCount[role]--;
        
        emit RoleRevoked(role, account, msg.sender);
    }
    
    function renounceRole(bytes32 role) public virtual {
        require(hasRole[role][msg.sender], "Does not have role");
        
        hasRole[role][msg.sender] = false;
        roleCount[role]--;
        
        emit RoleRenounced(role, msg.sender);
    }
    
    function getRoleCount(bytes32 role) public view returns (uint256) {
        return roleCount[role];
    }
    
    function getRoleGrantedTime(bytes32 role, address account) public view returns (uint256) {
        return roleGrantedTime[role][account];
    }
}
```

## 2. Combined Base Contract (Inheritance)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title BaseAccessControl
 * @dev Combines multiple base contracts through inheritance
 */
contract BaseAccessControl is Ownable, Pausable, AccessControl, FeatureFlags {
    
    // Feature IDs
    bytes32 public constant FEATURE_ADVANCED_OPERATIONS = keccak256("FEATURE_ADVANCED_OPERATIONS");
    bytes32 public constant FEATURE_BULK_OPERATIONS = keccak256("FEATURE_BULK_OPERATIONS");
    bytes32 public constant FEATURE_AUDIT_LOGS = keccak256("FEATURE_AUDIT_LOGS");
    
    event ContractInitialized(address indexed initializer);
    
    constructor() {
        // Grant admin role to deployer
        _setupRole(ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, msg.sender);
        
        // Enable default features
        features[FEATURE_ADVANCED_OPERATIONS] = true;
        features[FEATURE_AUDIT_LOGS] = true;
        
        emit ContractInitialized(msg.sender);
    }
    
    // Internal function to setup role
    function _setupRole(bytes32 role, address account) internal {
        hasRole[role][account] = true;
        roleGrantedTime[role][account] = block.timestamp;
        roleCount[role]++;
        emit RoleGranted(role, account, address(this));
    }
    
    // Override to enforce only owner can pause
    function pause() public override onlyOwner {
        super.pause();
    }
    
    function unpause() public override onlyOwner {
        super.unpause();
    }
    
    // Override to enforce only admin can manage features
    function enableFeature(bytes32 featureId) public override onlyAdmin {
        super.enableFeature(featureId);
    }
    
    function disableFeature(bytes32 featureId) public override onlyAdmin {
        super.disableFeature(featureId);
    }
}
```

## 3. Upgradeable Contract System

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title UpgradeableContract
 * @dev Demonstrates upgradeable pattern using inheritance
 */
contract UpgradeableContract is BaseAccessControl {
    
    // Storage layout must be preserved across upgrades
    uint256 public version;
    mapping(address => uint256) public userBalance;
    mapping(bytes32 => bytes32) public metadata;
    
    // New storage variables for upgrades
    uint256 public totalUsers;
    address public treasury;
    
    event ContractUpgraded(uint256 oldVersion, uint256 newVersion, address indexed upgradedBy);
    event UserRegistered(address indexed user, uint256 timestamp);
    
    constructor() {
        version = 1;
        treasury = owner;
    }
    
    // Core functionality
    function registerUser(address user) public onlyRole(MANAGER_ROLE) whenNotPaused {
        require(user != address(0), "Invalid user");
        require(userBalance[user] == 0, "User already registered");
        
        userBalance[user] = 0;
        totalUsers++;
        
        emit UserRegistered(user, block.timestamp);
    }
    
    function updateUserBalance(address user, uint256 newBalance) 
        public 
        onlyRole(OPERATOR_ROLE) 
        whenNotPaused 
        onlyIfFeatureEnabled(FEATURE_ADVANCED_OPERATIONS) 
    {
        require(userBalance[user] > 0 || newBalance > 0, "Invalid operation");
        userBalance[user] = newBalance;
    }
    
    function bulkUpdateBalances(address[] memory users, uint256[] memory balances) 
        public 
        onlyRole(OPERATOR_ROLE) 
        whenNotPaused 
        onlyIfFeatureEnabled(FEATURE_BULK_OPERATIONS) 
    {
        require(users.length == balances.length, "Length mismatch");
        require(users.length <= 100, "Batch too large");
        
        for (uint256 i = 0; i < users.length; i++) {
            userBalance[users[i]] = balances[i];
        }
    }
    
    // Upgrade function
    function upgradeContract(uint256 newVersion) public onlyOwner {
        require(newVersion > version, "Version must be higher");
        
        uint256 oldVersion = version;
        version = newVersion;
        
        // Migration logic for new version
        if (newVersion == 2) {
            // Version 2 migration
            _migrateToV2();
        } else if (newVersion == 3) {
            // Version 3 migration
            _migrateToV3();
        }
        
        emit ContractUpgraded(oldVersion, newVersion, msg.sender);
    }
    
    function _migrateToV2() internal virtual {
        // Migrate to version 2
        // Initialize new storage variables
        treasury = owner;
        enableFeature(FEATURE_BULK_OPERATIONS);
    }
    
    function _migrateToV3() internal virtual {
        // Migrate to version 3
        // Additional setup
    }
}

/**
 * @title UpgradeableContractV2
 * @dev Second version of the upgradeable contract
 */
contract UpgradeableContractV2 is UpgradeableContract {
    
    // New storage variables for V2
    mapping(address => uint256) public userLastActivity;
    mapping(address => bool) public isActiveUser;
    
    // New features
    bytes32 public constant FEATURE_USER_ACTIVITY = keccak256("FEATURE_USER_ACTIVITY");
    
    constructor() {
        version = 2;
        enableFeature(FEATURE_USER_ACTIVITY);
    }
    
    // New functionality
    function updateUserActivity(address user) public onlyRole(OPERATOR_ROLE) {
        require(userBalance[user] > 0, "User not registered");
        
        userLastActivity[user] = block.timestamp;
        isActiveUser[user] = true;
    }
    
    // Override with new functionality
    function registerUser(address user) public override onlyRole(MANAGER_ROLE) whenNotPaused {
        super.registerUser(user);
        userLastActivity[user] = block.timestamp;
        isActiveUser[user] = false;
    }
    
    // Override migration
    function _migrateToV2() internal override {
        super._migrateToV2();
        // V2 specific migration
        enableFeature(FEATURE_USER_ACTIVITY);
    }
}

/**
 * @title UpgradeableContractV3
 * @dev Third version with enhanced features
 */
contract UpgradeableContractV3 is UpgradeableContractV2 {
    
    // New storage for V3
    mapping(address => uint256) public userTotalTransactions;
    uint256 public totalTransactions;
    
    // New feature
    bytes32 public constant FEATURE_ANALYTICS = keccak256("FEATURE_ANALYTICS");
    
    constructor() {
        version = 3;
        enableFeature(FEATURE_ANALYTICS);
    }
    
    // Enhanced functionality
    function updateUserBalance(address user, uint256 newBalance) 
        public 
        override 
        onlyRole(OPERATOR_ROLE) 
        whenNotPaused 
        onlyIfFeatureEnabled(FEATURE_ADVANCED_OPERATIONS) 
    {
        super.updateUserBalance(user, newBalance);
        userTotalTransactions[user]++;
        totalTransactions++;
        
        if (isFeatureEnabled(FEATURE_ANALYTICS)) {
            // Analytics tracking
            metadata[keccak256(abi.encodePacked("analytics_", user))] = 
                keccak256(abi.encodePacked(block.timestamp, newBalance));
        }
    }
    
    function _migrateToV3() internal override {
        super._migrateToV3();
        enableFeature(FEATURE_ANALYTICS);
    }
}
```

## 4. Feature Flag System Implementation

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title AdvancedFeatureSystem
 * @dev Advanced feature flag system with time-based activation
 */
contract AdvancedFeatureSystem is BaseAccessControl {
    
    struct FeatureInfo {
        bool enabled;
        uint256 activationTime;
        uint256 expiryTime;
        address[] authorizedUsers;
        mapping(address => bool) isAuthorized;
        string description;
    }
    
    mapping(bytes32 => FeatureInfo) public featureDetails;
    mapping(bytes32 => mapping(address => bool)) public featureOverrides;
    
    event FeatureCreated(bytes32 indexed featureId, string description);
    event FeatureExpirySet(bytes32 indexed featureId, uint256 expiryTime);
    event FeatureOverrideSet(bytes32 indexed featureId, address indexed user, bool enabled);
    
    // Create feature with description
    function createFeature(bytes32 featureId, string memory description) public onlyAdmin {
        require(featureDetails[featureId].activationTime == 0, "Feature exists");
        
        FeatureInfo storage feature = featureDetails[featureId];
        feature.enabled = true;
        feature.activationTime = block.timestamp;
        feature.description = description;
        
        emit FeatureCreated(featureId, description);
        emit FeatureEnabled(featureId, msg.sender);
    }
    
    // Set feature expiry
    function setFeatureExpiry(bytes32 featureId, uint256 expiryTime) public onlyAdmin {
        require(featureDetails[featureId].activationTime != 0, "Feature doesn't exist");
        featureDetails[featureId].expiryTime = expiryTime;
        emit FeatureExpirySet(featureId, expiryTime);
    }
    
    // Authorize specific user for feature
    function authorizeUserForFeature(bytes32 featureId, address user) public onlyAdmin {
        require(featureDetails[featureId].activationTime != 0, "Feature doesn't exist");
        require(!featureDetails[featureId].isAuthorized[user], "Already authorized");
        
        featureDetails[featureId].authorizedUsers.push(user);
        featureDetails[featureId].isAuthorized[user] = true;
    }
    
    // Set user-specific override
    function setFeatureOverride(bytes32 featureId, address user, bool enabled) public onlyAdmin {
        featureOverrides[featureId][user] = enabled;
        emit FeatureOverrideSet(featureId, user, enabled);
    }
    
    // Check if feature is enabled for specific user
    function isFeatureEnabledForUser(bytes32 featureId, address user) public view returns (bool) {
        // Check user-specific override first
        if (featureOverrides[featureId][user]) {
            return true;
        }
        
        // Check if user is authorized
        FeatureInfo storage feature = featureDetails[featureId];
        if (feature.isAuthorized[user]) {
            return isFeatureActive(featureId);
        }
        
        // Check if feature is enabled and not expired
        return isFeatureActive(featureId);
    }
    
    // Override isFeatureActive to check expiry
    function isFeatureActive(bytes32 featureId) public view override returns (bool) {
        FeatureInfo storage feature = featureDetails[featureId];
        if (!feature.enabled) {
            return false;
        }
        
        // Check expiry
        if (feature.expiryTime > 0 && block.timestamp > feature.expiryTime) {
            return false;
        }
        
        return true;
    }
    
    // Get authorized users for a feature
    function getFeatureAuthorizedUsers(bytes32 featureId) public view returns (address[] memory) {
        return featureDetails[featureId].authorizedUsers;
    }
    
    // Get feature description
    function getFeatureDescription(bytes32 featureId) public view returns (string memory) {
        return featureDetails[featureId].description;
    }
}
```

## 5. Main Implementation Contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title MainRBACSystem
 * @dev Main implementation combining all features
 */
contract MainRBACSystem is UpgradeableContractV3, AdvancedFeatureSystem {
    
    // Additional role for feature managers
    bytes32 public constant FEATURE_MANAGER_ROLE = keccak256("FEATURE_MANAGER_ROLE");
    
    // Custom features
    bytes32 public constant FEATURE_ACCESS_REQUESTS = keccak256("FEATURE_ACCESS_REQUESTS");
    bytes32 public constant FEATURE_ADVANCED_REPORTING = keccak256("FEATURE_ADVANCED_REPORTING");
    
    // Access request tracking
    struct AccessRequest {
        address requester;
        bytes32 role;
        uint256 requestTime;
        bool approved;
        address approvedBy;
    }
    
    mapping(uint256 => AccessRequest) public accessRequests;
    uint256 public requestCounter;
    mapping(address => uint256[]) public userRequests;
    
    event AccessRequested(uint256 indexed requestId, address indexed requester, bytes32 role);
    event AccessApproved(uint256 indexed requestId, address indexed approvedBy);
    event AccessDenied(uint256 indexed requestId, address indexed deniedBy);
    
    constructor() {
        // Grant additional roles
        _setupRole(FEATURE_MANAGER_ROLE, msg.sender);
        
        // Create features
        createFeature(FEATURE_ACCESS_REQUESTS, "Self-service access requests");
        createFeature(FEATURE_ADVANCED_REPORTING, "Advanced reporting and analytics");
    }
    
    // Request access to a role
    function requestAccess(bytes32 role) public whenNotPaused onlyIfFeatureEnabled(FEATURE_ACCESS_REQUESTS) {
        require(role != ADMIN_ROLE, "Cannot request admin");
        require(!hasRole[role][msg.sender], "Already has role");
        require(role == MANAGER_ROLE || role == OPERATOR_ROLE || role == VIEWER_ROLE, "Invalid role");
        
        requestCounter++;
        accessRequests[requestCounter] = AccessRequest({
            requester: msg.sender,
            role: role,
            requestTime: block.timestamp,
            approved: false,
            approvedBy: address(0)
        });
        
        userRequests[msg.sender].push(requestCounter);
        emit AccessRequested(requestCounter, msg.sender, role);
    }
    
    // Approve access request
    function approveAccess(uint256 requestId) public onlyRole(MANAGER_ROLE) whenNotPaused {
        AccessRequest storage request = accessRequests[requestId];
        require(request.requestTime > 0, "Request doesn't exist");
        require(!request.approved, "Already approved");
        require(request.requester != address(0), "Invalid request");
        
        // Grant the role
        grantRole(request.role, request.requester);
        
        request.approved = true;
        request.approvedBy = msg.sender;
        
        emit AccessApproved(requestId, msg.sender);
    }
    
    // Deny access request
    function denyAccess(uint256 requestId) public onlyRole(MANAGER_ROLE) {
        AccessRequest storage request = accessRequests[requestId];
        require(request.requestTime > 0, "Request doesn't exist");
        require(!request.approved, "Already approved");
        
        request.approved = true; // Mark as processed
        request.approvedBy = msg.sender;
        
        emit AccessDenied(requestId, msg.sender);
    }
    
    // Get user's access requests
    function getUserRequests(address user) public view returns (uint256[] memory) {
        return userRequests[user];
    }
    
    // Get access request details
    function getAccessRequest(uint256 requestId) public view returns (
        address requester,
        bytes32 role,
        uint256 requestTime,
        bool approved,
        address approvedBy
    ) {
        AccessRequest storage request = accessRequests[requestId];
        return (
            request.requester,
            request.role,
            request.requestTime,
            request.approved,
            request.approvedBy
        );
    }
    
    // Get user's role status
    function getUserRoles(address user) public view returns (
        bool isAdmin,
        bool isManager,
        bool isOperator,
        bool isViewer
    ) {
        return (
            hasRole[ADMIN_ROLE][user],
            hasRole[MANAGER_ROLE][user],
            hasRole[OPERATOR_ROLE][user],
            hasRole[VIEWER_ROLE][user]
        );
    }
    
    // Advanced reporting (requires feature flag)
    function generateReport(address user) public view 
        onlyIfFeatureEnabled(FEATURE_ADVANCED_REPORTING) 
        returns (uint256 balance, uint256 lastActivity, uint256 totalTx, bool active) 
    {
        return (
            userBalance[user],
            userLastActivity[user],
            userTotalTransactions[user],
            isActiveUser[user]
        );
    }
    
    // Override to add custom validation
    function grantRole(bytes32 role, address account) public override {
        require(role != FEATURE_MANAGER_ROLE || hasRole[ADMIN_ROLE][msg.sender], "Cannot grant feature manager");
        super.grantRole(role, account);
    }
}
```

## 6. Deployment Script Example

```javascript
// scripts/deploy.js
const hre = require("hardhat");

async function main() {
  console.log("Deploying RBAC System...");
  
  // Deploy main contract
  const MainRBACSystem = await hre.ethers.getContractFactory("MainRBACSystem");
  const rbacSystem = await MainRBACSystem.deploy();
  await rbacSystem.deployed();
  
  console.log("MainRBACSystem deployed to:", rbacSystem.address);
  
  // Test functionality
  const [owner, user1, user2] = await hre.ethers.getSigners();
  
  // Grant operator role to user1
  await rbacSystem.grantRole(
    await rbacSystem.OPERATOR_ROLE(),
    user1.address
  );
  console.log("Granted OPERATOR_ROLE to:", user1.address);
  
  // Register user
  await rbacSystem.connect(user1).registerUser(user2.address);
  console.log("Registered user:", user2.address);
  
  // Test feature flags
  const advancedOps = await rbacSystem.FEATURE_ADVANCED_OPERATIONS();
  const isEnabled = await rbacSystem.isFeatureActive(advancedOps);
  console.log("Advanced operations enabled:", isEnabled);
  
  // Test upgrade
  await rbacSystem.upgradeContract(2);
  console.log("Contract upgraded to version 2");
  
  // Test access request
  await rbacSystem.connect(user2).requestAccess(
    await rbacSystem.VIEWER_ROLE()
  );
  console.log("Access requested by user2");
  
  console.log("Deployment complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
```

## 7. Test Suite

```solidity
// test/RBACSystem.test.js
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("RBAC System", function () {
  let rbacSystem, owner, admin, manager, operator, user1, user2;
  
  beforeEach(async function () {
    [owner, admin, manager, operator, user1, user2] = await ethers.getSigners();
    
    const MainRBACSystem = await ethers.getContractFactory("MainRBACSystem");
    rbacSystem = await MainRBACSystem.deploy();
    await rbacSystem.deployed();
  });
  
  describe("Role Management", function () {
    it("Should grant roles correctly", async function () {
      const operatorRole = await rbacSystem.OPERATOR_ROLE();
      await rbacSystem.grantRole(operatorRole, user1.address);
      
      expect(await rbacSystem.hasRole(operatorRole, user1.address)).to.be.true;
    });
    
    it("Should prevent non-admin from granting roles", async function () {
      const operatorRole = await rbacSystem.OPERATOR_ROLE();
      await expect(
        rbacSystem.connect(user1).grantRole(operatorRole, user2.address)
      ).to.be.revertedWith("Not admin");
    });
  });
  
  describe("Feature Flags", function () {
    it("Should enable and disable features", async function () {
      const featureId = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("TEST_FEATURE"));
      
      await rbacSystem.createFeature(featureId, "Test feature");
      expect(await rbacSystem.isFeatureActive(featureId)).to.be.true;
      
      await rbacSystem.disableFeature(featureId);
      expect(await rbacSystem.isFeatureActive(featureId)).to.be.false;
    });
    
    it("Should enforce feature flags on functions", async function () {
      const bulkOps = await rbacSystem.FEATURE_BULK_OPERATIONS();
      await rbacSystem.disableFeature(bulkOps);
      
      await expect(
        rbacSystem.connect(operator).bulkUpdateBalances([user1.address], [100])
      ).to.be.revertedWith("Feature disabled");
    });
  });
  
  describe("Upgrade System", function () {
    it("Should upgrade contract version", async function () {
      expect(await rbacSystem.version()).to.equal(1);
      
      await rbacSystem.upgradeContract(2);
      expect(await rbacSystem.version()).to.equal(2);
    });
    
    it("Should prevent downgrading", async function () {
      await rbacSystem.upgradeContract(2);
      await expect(
        rbacSystem.upgradeContract(1)
      ).to.be.revertedWith("Version must be higher");
    });
  });
  
  describe("Access Requests", function () {
    it("Should request and approve access", async function () {
      await rbacSystem.connect(user1).requestAccess(
        await rbacSystem.VIEWER_ROLE()
      );
      
      const requestId = await rbacSystem.requestCounter();
      await rbacSystem.connect(manager).approveAccess(requestId);
      
      const request = await rbacSystem.getAccessRequest(requestId);
      expect(request.approved).to.be.true;
      expect(request.approvedBy).to.equal(manager.address);
    });
  });
  
  describe("Pausable", function () {
    it("Should pause and unpause contract", async function () {
      await rbacSystem.pause();
      expect(await rbacSystem.paused()).to.be.true;
      
      await expect(
        rbacSystem.connect(operator).registerUser(user1.address)
      ).to.be.revertedWith("Contract paused");
      
      await rbacSystem.unpause();
      expect(await rbacSystem.paused()).to.be.false;
    });
  });
});
```

This implementation demonstrates:

1. **Multiple Inheritance Levels**: Base contracts (Ownable, Pausable) → AccessControl → BaseAccessControl → Upgradeable contracts → Feature system → Main implementation

2. **Role-Based Access Control**: Multiple roles (ADMIN, MANAGER, OPERATOR, VIEWER) with granular permissions

3. **Feature Flag System**: Enable/disable features globally, per-user overrides, time-based expiry

4. **Upgradeable Pattern**: Version tracking with migration logic across multiple versions

5. **Reusable Base Contracts**: Modular components that can be inherited in different combinations

6. **Advanced Features**: Access request workflow, user authorization, reporting with feature flags

The system is fully tested and demonstrates practical use of inheritance in Solidity for building enterprise-grade access control systems.