pragma solidity ^0.8.0;

import "./Day14-BaseDepositBox.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
\import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

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


// MultiSigDepositBox Storage visual -
// ┌─────────────────────────────┐
// │ BaseDepositBox (inherited)  │
// ├─────────────────────────────┤
// │ owner:      0x1234...       │
// │ secret:     "my-secret"     │
// │ depositTime: 1234567890     │
// ├─────────────────────────────┤
// │ MultiSig (extended)         │
// ├─────────────────────────────┤
// │ owners[]:                   │
// │  [0] 0xabcd...              │
// │  [1] 0xefgh...              │
// │  [2] 0xijkl...              │
// │                             │
// │ isOwner mapping:            │
// │  0xabcd... → true           │
// │  0xefgh... → true           │
// │                             │
// │ requiredApprovals: 2        │
// │ requestCounter: 5           │
// │                             │
// │ requests[1]:                │
// │  requester: 0xabcd...       │
// │  secret: "my-secret"        │
// │  executed: false            │
// │  timestamp: 1234567890      │
// │                             │
// │ approvals[1]:               │
// │  0xabcd... → true           │
// │  0xefgh... → true           │
// └─────────────────────────────┘


contract NFTDepositBox is BaseDepositBox, IERC721Receiver, IERC1155Receiver{
    using EnumerableSet for EnumerableSet.UniSet;
    using EnumerableSet for EnumerableSet.AddressSet;

   struct StoredNFT{
     address contractAddress;
     uint256 tokenId;
     uint256 amount;
     string tokenType;
     uint256 depositedAt;
     bool isWithdrawn;
   }
   EnumerableSet.UintSet private nftIndexes;
   mapping(uint256 => StoredNFT) public storedNFTs;
   mapping(address => EnumerableSet.UintSet) private userNFTs;

   // Additional metadata storage
    struct NFTMetadata {
        string name;
        string symbol;
        string tokenURI;
        string[] attributes;
    }
    mapping(uint256 => NFTMetadata) public nftMetadata;

   event NFTDeposited(
    uint256 indexed nftIndex,
    address indexed depositor,
    address indexed nftContract,
    uint256 tokenId,
    string tokenType
   );
   event NFTWithdrawn(
     uint256 indexed nftIndex,
     address indexed receiver
   );

   modifier validNFT(uint256 nftIndex) {
        require(nftIndex > 0 && nftIndex <= nftIndexes.length(), "Invalid NFT");
        require(!storedNFTs[nftIndex].isWithdrawn, "NFT already withdrawn");
        _;
    }
    
    // Deposit ERC721 NFT
    function depositERC721(
        address nftContract,
        uint256 tokenId
    ) external{
        IERC721 nft = IERC721(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Not the owner");

        nft.safeTransferFrom(msg.sender, address(this), tokenId);
        _storeNFT(nftContract, tokenId, 1, "ERC721");
    }

    // Deposit ERC1155 NFT
    function depositERC1155(
        address nftContract,
        uint256 tokenId,
        uint256 amount
    )external {
        IERC1155 neft = IERC1155(nftContract);
        require(nft.balanceOf(msg.sender, tokenId) >= amount, "Insufficient balance");

        nft.safeTransferFrom(msg.sender, address(this), tokenId, amount, "");
        _storeNFT(nftContract, tokenId, amount, "ERC1155");
    }

    // Deposit multiple NFTs at once
    function depositMultipleERC721(
        address nftContract,
        uint256[] calldata tokenIds
    ) external {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            depositERC721(nftContract, tokenIds[i]);
        }
    }

    function deepositERC721Metadata(
        address nftContract,
        uint256 tokenId
    ) external{
        // first deposit NFT
        depositERC721(nftContract, tokenId);
        uint256 nftIndex = nftIndexes.length() -1;
        IERC721Metadata nft = IERC721Metadata(nftContract);

        try nft.name() returns (string memory name) {
            nftMetadata[nftIndex].name = name;
        } catch {}
        
        try nft.symbol() returns (string memory symbol) {
            nftMetadata[nftIndex].symbol = symbol;
        } catch {}
        
        try nft.tokenURI(tokenId) returns (string memory uri) {
            nftMetadata[nftIndex].tokenURI = uri;
        } catch {}
    }

    // View function for NFT metadata
    function getNFTMetadata(uint256 nftIndex) external view 
        validNFT(nftIndex) 
        returns (
            string memory name,
            string memory symbol,
            string memory tokenURI
        )
    {
        return (
            nftMetadata[nftIndex].name,
            nftMetadata[nftIndex].symbol,
            nftMetadata[nftIndex].tokenURI
        );
    }

    function _storeNFT(
        address nftContract,
        uint256 tokenId,
        uint256 amount,
        string memory tokenType
    ) private {
        // Get next index
        uint256 nftIndex = nftIndexes.length() + 1;
        nftIndexes.add(nftIndex);
        
        // Store NFT details
        storedNFTs[nftIndex] = StoredNFT({
            contractAddress: nftContract,
            tokenId: tokenId,
            amount: amount,
            tokenType: tokenType,
            depositedAt: block.timestamp,
            isWithdrawn: false
        });

        // Track by user
        userNFTs[msg.sender].add(nftIndex);
        emit NFTDeposited(nftIndex, msg.sender, nftContract, tokenId, tokenType);
    }

    function withdrawal(uint256 nftIndex) external validNFT(nftIndex){
        StoredNFT storage nft = storedNFTs[nftIndex];
        require(!nft.isWithdrawn ,"Already withdrawn");
        require(nft.ownerOf(nft.tokenId)== msg.sender, "Not Auth");
        nft.isWithdrawn = true;

        if(keccak256(bytes(nft.tokenType)) == keccak256(bytes("ERC721"))){
            IERC721(nft.contractAddress).safeTransferFrom(
                address(this),
                msg.sender,
                nft.tokenId
            )
        } else if(keccak256(bytes(nft.tokenType)) == keccak256(bytes("ERC1155"))){
            IERC1155(nft.contractAddress).safeTransferFrom(
                address(this),
                msg.sender,
                nft.tokenId,
                nft.amount,
                ""
            )
        }
        emit NFTWithdrawn(nftIndex, msg.sender);
    }

      function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId ||
               interfaceId == type(IERC1155Receiver).interfaceId;
    }
}

contract NFTGallery {
    // Allow users to view their NFTs across multiple vaults
    struct NFTView {
        address vaultAddress;
        uint256 nftIndex;
        address nftContract;
        uint256 tokenId;
        string tokenType;
        uint256 depositedAt;
    }
    
    function getUserNFTsAcrossVaults(
        address user,
        address[] memory vaultAddresses
    ) external view returns (NFTView[] memory) {
        uint256 totalNFTs = 0;
        
        // Count total NFTs across vaults
        for (uint256 i = 0; i < vaultAddresses.length; i++) {
            NFTDepositBox vault = NFTDepositBox(vaultAddresses[i]);
            uint256[] memory userNFTs = vault.getUserNFTs(user);
            totalNFTs += userNFTs.length;
        }
        
        // Build array of NFTs
        NFTView[] memory nfts = new NFTView[](totalNFTs);
        uint256 currentIndex = 0;
        
        for (uint256 i = 0; i < vaultAddresses.length; i++) {
            NFTDepositBox vault = NFTDepositBox(vaultAddresses[i]);
            uint256[] memory userNFTs = vault.getUserNFTs(user);
            
            for (uint256 j = 0; j < userNFTs.length; j++) {
                uint256 nftIndex = userNFTs[j];
                (
                    address nftContract,
                    uint256 tokenId,
                    ,
                    string memory tokenType,
                    uint256 depositedAt,
                    
                ) = vault.getNFTDetails(nftIndex);
                
                nfts[currentIndex] = NFTView({
                    vaultAddress: vaultAddresses[i],
                    nftIndex: nftIndex,
                    nftContract: nftContract,
                    tokenId: tokenId,
                    tokenType: tokenType,
                    depositedAt: depositedAt
                });
                
                currentIndex++;
            }
        }
        
        return nfts;
    }
}