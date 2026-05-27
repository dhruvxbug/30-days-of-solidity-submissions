// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30; //our solidity version 

// to get balance
interface IERC20{
    function balanceOf(address account) external view returns(uint256);
}

contract PollStation{
    bytes32[] public candidateNames; // array of names of candidates
    mapping(bytes32 => uint256) voteCount; // vote count - candidateName
    mapping(address => bool) hasVoted; // address - true/false (already voted?) (address of the voter not the candidate)
    mapping(bytes32 => bool) isCandidate;  // candidateName - true/false (valid user?)
    address public admin; // admin address
    uint256 public votingStart; 
    uint256 public votingEnd; 
    mapping (address => bytes32) public voterChoice; // history 
    event Voted(address indexed voter, string candidate, uint256 timestamp)
    
    address public tokenAddress; // address of ERC20 token
    IERC20 public token;
    event BalanceChecked(address indexed user, uint256 balance); // only for storage

    // new logic 
    struct VoteSubmission{
        string[] rankings;
        uint256 weight;
        bool hasVoted
    }

    mapping(address => VoteSubmission) public votes;
    address[] public voters;

    mapping(string => bool) public eliminated; // eliminate candidate
    uint256 public totalActiveVotes; // active votes 
    mapping(uint256 => mapping(string => uint256)) public roundResults; // results 
    unint256 public currentRound; // no. of rounds till now
    string public winner;  // final winner
    bool public electionComplete; 

    //events 
    event VoteSubmitted(address indexed voter, uint256 weight,uint256 rankingCount);
    event RoundComplete(uint256 round, string eliminatedCandidate, uint256 lowestVotes);
    event Winner Declared(string winner, uint256 finalRound);

    constructor(){ // created this constructor to create Admin variable which will be allowed to create candidates
        admin = msg.sender;
    }

    constructor(uint256 _durationInDays) {
    votingStart = block.timestamp;
    votingEnd = block.timestamp + (_durationInDays * 1 days);
}

    modifier onlyAdmin(){ // require funcion like condition before another function 
        require(msg.sender == admin, "Not admin");
        _;
    }

    function checkCallerBalance() external{
        uint256 balance = token.balanceOf(msg.sender);
    }

    // old func
    function addCandidateNames(string memory _candidateNames)public onlyAdmin{
        candidateNames.push(_candidateNames);
        isCandidate[_candidateNames] = true;
        voteCount[_candidateNames]=0;
    }

    // old func 
    function getCandidateNames() public view returns(string[] memory){
        return candidateNames;
    }

    // old func
    function addVote(string memory _candidateNames)public{
        //time stamp check
        require(block.timestamp >= votingStart, "Voting not started");
        require(block.timestamp <= votingEnd," Voting Ended");

        // valid candidate? and voted? 
        require(isCandidate[_candidateNames],"Invalid candidate");
        require(!hasVoted[msg.sender],"Already Voted");

        // weight of vote??
        uint256 weight = checkCallerBalance(msg.sender);
        require(weight>0 ,"No voting power");
        emit BalanceChecked(msg.sender,weight);

        // marking vote true
        hasVoted[msg.sender] = true;
        // select candidate - history 1 (mapping)
        voterChoice[msg.sender] = _candidateNames;
        // creating history 2 (event)
        emit Voted(msg.sender, _candidateNames, block.timestamp);
        // increase vote count for candiate selected 
        voteCount[_candidateNames] += 1;
    }

    // old func
    function getVotes(string memory _candidateNames)public view returns(unint256){
        return voteCount[_candidateNames];
    }

    // old func
    function getWinner() public view returns(string memory winner, uint256 winningVoteCount){
        require(block.timestamp > votingEnd, "Voting still actie")
        winningVoteCount = 0;
        uint256 length = candidateNames.length;
        for(uint i=0; i< length; i++){
            uint256 votes = voteCount[candidateNames[i]];
            if(votes >winningVoteCount){
                winningVoteCount= votes;
                winner = candidateNames[i];
            }
        }
    }    

    // === Phase 1 -- Submit Rankings ===
     function submitRankings(string[] memory _rankings) external{
        //time stamp check
        require(block.timestamp >= votingStart, "Voting not started");
        require(block.timestamp <= votingEnd," Voting Ended");

        // valid candidate? and voted? 
        require(isCandidate[_candidateNames],"Invalid candidate");
        require(!hasVoted[msg.sender],"Already Voted");

        // votings 
        require(_rankings.length <= candidates.length, "Too many rankings");
        require(_rankings.length >= 1, "Atleast one ranking");

        // candidate validity + duplication check 
        for(uint i=0; i< _rankings.length; i++){
            require(isCandidate[_rankings[i]], "Invalid Candidate");
            for(unint j = i+1; j< _rankings.length; j++){
                require(keccak256(bytes(_rankings[i]))) != keccak256(bytes(_rankings[i]), "Duplicate Candidate");
            }
        }

        // voting power check 
        uint256 weight = checkCallerBalance(msg.sender);
        require(weight>0, "No voting power");

        votes[msg.sender] = VoteSubmission({
            rankings: _rankings,
            weight: weight,
            hasVoted: true
        });

        voters.push(msg.sender);
        totalActiveVotes += weight;

        emit VoteSubmitted(msg.sender, weight, _rankings.length);
    }

    // === Phase 2 : Count Current Round ====
    function getCurrentTopChoice(address voter) public view returns (string memory){
        VoteSubmission storage v = votes[voter]; // voters ballot data from storage
        for (uint i=0; i < v.rankings.length; i++){
            if(!eliminated[v.rankings[i]]){
                return v.rankings[i]     // return current candidate as top choice 
            }
        }
        return "";
    }

    function countCurrentRound() public view returns(mappings(string => uint256) memory counts, uint256 total){
        // create a pointer to where round results are stored 
        mapping(string => uint256) storage counts = roundResults[currentRound]; 
        uint256 totalVotes = 0; 

        for(uint i = 0; i < voters.length; i++){ // every registered voter
            address voter = voters[i]; 
            // getting top choice of every voter 
            string memory topChoice = getCurrentTopChoice(voter);

            if(keccak256(bytes(topChoice)) != keccak256(bytes(""))){ // if they still have a valid choice - no empty string
                counts[topChoice] += votes[voter].weight;  // adding voters power to the top choice candidate
                totalVotes += votes[voter].weight;         // adding voters power to the total Votes
             }
        }
        return (counts, totalVotes);  // counts -> votes (round results)
    }

    // === Phase 3 : Elimination Logic ===
    function findLowestCandidate() public view returns( string memory lowest, uint256 lowestVotes){
        require(!electionComplete, "Election Complete"); // election needs to be incomplete 

        lowestVotes = type(uint256).max;
        string memory lowestCandidate;
        bool foundAny = false;

        for(uint i =0; i< candidates.length; i++){
            string memory candidate = candidates[i];
            if(!eliminated[candiate]){
                uint256 votes = roundResults[currentRound][candidate];
                if(votes < lowestVotes){
                    lowestVotes = votes;
                    lowestCandidate = candidate;
                    foundAny = true;
                }
            }
        }
        require(foundAny, "No active candidates");
        return(lowestCandidate, lowestVotes);
    }

    function checkMajority() public view returns(bool hasWinner, string memory winningCandidate){
        uint256 total =0;
        mapping(string => uint256) storage results = roundResults[currentRound];

        for(uint i=0; i<candidates.length; i++){
            if(!eliminated[candidate[i]]){
                total += results[candiate[i]];
            }
        }

        uint256 threshold = total/2; //simple majority 

        for(uint i=0; i< candidates.length; i++){
            string memory candidate = candidates[i];
            if(!eliminated[candidate] && results[candidate] > threshold){
                return (true, candidate);
            }
        }

        return(false, "");
    }

    // === Phase 4 : Elimination Round ===
    function runEliminationRound() external{
        require(block.timestamp > votingEnd, "Voting still active");
        require(!electionComplete, "Election already complete");
        require(currentRound == 0 || roundResults[currentRound][candidates[0]] != 0, "Run countRound first");

        (bool hasWinner, string memory winningCandidate) = checkMajority();
        if( hasWinner){
            winner = winningCandidate;
            electionComplete = true;
            emit WinnerDeclared(winner, currentRound);
            return;
        }

        (string memory lowest, uint256 lowestVotes) = findLowestCandidate();
        eliminated[lowest] = true;

        emit RoundComplete(currentRound, lowest, lowestVotes);
        currentRound++;

        recountForNextRound();
    }

    function recountForNextRound() internal{
        mapping(string => uint256) storage newResults = roundResults[currentRound];

        for(uint i=0; i< voters.length; i++){
            address voter = voters[i];
            string memory topChoice = getCurrentTopChoice(voter);
            if(keccak256(bytes(topChoice)) != keccak256(bytes(""))){
                newResults[topChoice] += votes[voter].weight;
            }
        }
    }
}