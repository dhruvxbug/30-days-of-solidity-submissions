// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30; //our solidity version 

contract SaveMyName{
    string public name;
    uint256 public age;
    address public owner;
    string public bio;
    bool public isAdult;

    function add(string memory _name, string memory _bio) public{ 
        name = _name;
        bio = _bio;
    } 

    // no gas consumption as only a "view" function 
    function retrieve() public view returns (string memory, string memory){
        return(name, bio);
    }

   // combine compact version
    function addAndRetrieve(string memory newName, string memory newBio) public returns(string memory, string memory){
        name = newName;
        bio = newBio;
        return (name,bio);
    }

    //call data 
    function add1(string calldata _name , string calldata _bio) external{
        name = _name;
        bio = _bio;
    }

    //comparing string 
    function isNameAlice(string memory _name) public pure returns(bool){
        return keccak256(abi.encodePacked(_name)) == keccak256(abi.encodePacked("Alice"));
    }

    //convert to bytes for manipulation
    function toBytes(string memory _str) public pure returns(uint) {
        return bytes(_str).length;
    }
}

contract Learn{
    // using string is expensive 
    string public name;
    // use bytes32 when you can
    bytes32 public newName;

    // 50% gas reduction for short string
    function setName(string memory _name) public{
        require(bytes(_name).length<=32, "name too long");
        name = bytes32(bytes(_name));
    }

    function getName() public view returns (string memory){
        return string(abi.encodePacked(name));
    }

    // concatenation - adding 2 strings
    function concatenate(string memory a, string memory b) public pure returns(string memory){
        return string(abi.encodePacked(a,b));
    }

    // multiple return values 
    function getUserInfo() public view returns(string memory, uint256){
        return (name, block.timestamp);
    }
}

// Real world usecase 
contract RealWorldUseCases{
    // 1. ENS - Ethereum Name Service 
    // node - name of the domain , string - address ??
    mapping(bytes32 => string) public names;
    function setName(bytes32 node, string memory name) public{
        names[node] = name;
    }
 
    // 2. NFT metadata 
    mapping(uint256 => string) private _tokenURIs;
    function tokenURI(uint256 tokenId) public view returns (string memory){
        return _tokenURIs[tokenId];
    }

    // 3. Social Profiles 
    struct Profile{
        string username;
        string bio;
        string avatarURL;
    }
    mapping(address => Profile) public profiles;
}


// Gas Optimization
contract GasOptimization{

    // 1. Events are cheaper than storage 
    event NameChanged(address indexed user, string newName, uint256 timestamp);
    function setName(string memory _name) public {
        emit NameChanged(msg.sender, _name, block.timestamp);
    }

    // 2. Store hashes instead of full strings 
    mapping(address => string) public documents; //expensive
    mapping(address => bytes32) public documentHashes; //cheaper 
    function storeDocument(string memory doc) public{
        documentHashes[msg.sender] = keccak256(abi.encodePacked(doc));
    }
    function verifyDocument(string memory doc) public view returns(bool){
        return documentHashes[msg.sender] == keccak256(abi.encodePacked(doc));
    }

    // 3. use IPFS for Large text 
    mapping( address => string) public ipfsHashes;
    function setContent(string memory ipfsHash) public{
        ipfsHashes[msg.sender] = ipfsHash;
    }
}

//extend the contract 
// challenge 
contract ExtendedSaveMyName{
    string public firstName;
    string public userName;
    string public lastName;
    string public bio;

    // 2. concatenation
    function fullName(string memory a, string memory b) public pure returns(string memory){
        return string(abi.encodePacked(a,b));
    }

    // 3. username check 
    mapping(string => bool) private _userNamesTaken;
    function uniqueUserName(string memory _userName) public returns(bool){
        require(!_userNamesTaken[_userName], "Username is already Taken");
        userName = _userName;
        _userNamesTaken[_userName] = true;
        return true;
    }
    function isUserNameTaken(string memory _userName) public view returns(bool){
        return _userNamesTaken[_userName];
    }

    // 4. struct for multiple string profile
    struct Profile{
        string name;
        string bio;
    }
    mapping(address => Profile) public profiles;

    //5. IPFS integration for large text 
    mapping(address => string) public ipfsHashes;
    function setContent(string memory ipfsHash) public{
        ipfsHashes[msg.sender] = ipfsHash;
    }
}


// input example  - add("Alice", "Blockchain Developer");
// retrieve() → Returns ("Alice", "Blockchain Developer")


// uint256 public age = 25;   - Fixed size: 32 bytes
// bool public active = true; - Fixed size: 1 byte
// address public owner;      - Fixed size: 20 bytes

// string public name = "Alice";           - Variable size: 5 bytes
// string public bio = "Solidity dev...";  - Variable size: 15+ bytes