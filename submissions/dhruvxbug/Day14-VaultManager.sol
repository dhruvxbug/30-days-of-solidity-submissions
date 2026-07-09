pragma solidity ^0.8.0;

import "./Day14-IDepositBox.sol";
import "./Day14-ValutBoxes.sol";

contract VaultManager{
    mapping(address => IDepositBox[]) public userVaults;
    mapping(address => mapping(address => bool)) public vaultAccess;

    event VaultCreated(address indexed user, address vault, string vaultType);

    function createBasicVault() external returns(address){
      BasicDepositBox vault = new BasicDepositBox();
      userVaults[msg.sender].push(IDepositBox(address(vault)));
      emit VaultCreated(msg.sender, address(vault), "Basic");
      return address(vault);
    }

    function createPremiumVault() external returns(address){
        PremiumDepositBox vault = new PremiumDepositBox();
        userVaults[msg.sender].push(IDepositBox(address(vault)));
        return address(vault);
    }

    function createTimeLockedVault(uint256 lockDuration) external returns (address) {
        TimeLockedDepositBox vault = new TimeLockedDepositBox(lockDuration);
        userVaults[msg.sender].push(IDepositBox(address(vault)));
        emit VaultCreated(msg.sender, address(vault), "TimeLocked");
        return address(vault);
    }

    function createMultiSigVault(
        address[] memory owners,
        uint256 requiredApprovals
    ) external returns (address) {
        MultiSigDepositBox vault = new MultiSigDepositBox(owners, requiredApprovals);
        userVaults[msg.sender].push(IDepositBox(address(vault)));
        vaultAccess[address(vault)][msg.sender] = true;
        emit VaultCreated(msg.sender, address(vault), "MultiSig");
        return _addVault(address(vault), "MultiSig");
    }
    
    function getUserVaults(address user) external view returns (IDepositBox[] memory) {
        return userVaults[user];
    }

    function grantVaultAccess(address vaultAddress, address user) external {
        require(vaultAccess[vaultAddress][msg.sender], "Not vault owner");
        vaultAccess[vaultAddress][user] = true;
        emit VaultAccessGranted(vaultAddress, user);
    }

    function getVaultInfo(address vaultAddress) external view returns (
        string memory vaultType,
        address owner,
        uint256 depositTime
    ) {
        IDepositBox vault = IDepositBox(vaultAddress);
        return (
            vault.getBoxType(),
            vault.getOwner(),
            vault.getDepositTime()
        );
    }
}