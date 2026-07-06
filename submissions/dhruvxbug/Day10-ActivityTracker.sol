// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ActivityTracker {
    struct UserProfile {
        string name;
        uint256 weight; // in kg
        bool isRegistered;
        uint256 joinTimestamp;
        address[] followers;
        address[] following;
        bool isPublic; // Privacy setting
    }

    struct WorkoutActivity {
        string activityType;  // "Running", "Cycling", etc.
        uint256 duration;     // in seconds
        uint256 distance;     // in meters
        uint256 timestamp;    // when the workout happened
        uint256 caloriesBurned;
    }

    struct UserStats {
        uint256 totalWorkouts;
        uint256 totalDistance;
        uint256 totalDuration;
        uint256 averageWorkoutDuration;
        uint256 lastWorkoutTimestamp;
        string favoriteActivity;
        uint256 weeklyWorkouts; 
        uint256 monthlyWorkouts; 
    }

    struct ActivityFeed {
        address userAddress;
        string activityType;
        uint256 distance;
        uint256 timestamp;
        bool isWorkout;
    }
    ActivityFeed[] public globalFeed;
    uint256 public constant MAX_FEED_SIZE = 1000;

    mapping(address => UserProfile) public userProfiles;
    mapping(address => WorkoutActivity[]) private workoutHistory;
    mapping(address => uint256) public totalWorkouts;
    mapping(address => uint256) public totalDistance;
    mapping(address => uint256) public totalDuration;

    mapping(address => mapping(address => bool)) public isFollowing;
    mapping(address => address[]) public followersList;
    mapping(address => address[]) public followingList;
    mapping(address => bool) public isPublicProfile;

    event UserRegistered(address indexed userAddress, string name, uint256 timestamp);
    event ProfileUpdated(address indexed userAddress, uint256 newWeight, uint256 timestamp);
    event WorkoutLogged(address indexed userAddress, string activityType, uint256 duration, uint256 distance, uint256 timestamp);
    event MilestoneAchieved(address indexed userAddress, string milestone, uint256 timestamp);
    event Followed(address indexed follower, address indexed followed, uint256 timestamp);
    event Unfollowed(address indexed follower, address indexed followed, uint256 timestamp);
    event ProfileVisibilityUpdated(address indexed userAddress, bool isPublic);

    modifier onlyRegistered() {
        require(userProfiles[msg.sender].isRegistered, "User not registered");
        _;
    }

    modifier userExists(address _user) {
        require(userProfiles[_user].isRegistered, "User does not exist");
        _;
    }

    modifier notSelf(address _user) {
        require(msg.sender != _user, "Cannot follow/unfollow yourself");
        _;
    }

    modifier profileIsPublicOrFollowing(address _user) {
        require(
            isPublicProfile[_user] || isFollowing[msg.sender][_user],
            "Profile is private. Follow to view stats."
        );
        _;
    }

    function registerUser(string memory _name, uint256 _weight) public {
        require(!userProfiles[msg.sender].isRegistered, "User already registered");

        isPublicProfile[msg.sender] = true;

        userProfiles[msg.sender] = UserProfile({
            name: _name,
            weight: _weight,
            isRegistered: true,
            joinTimestamp: block.timestamp,
            followers: new address[](0),
            following: new address[](0),
            isPublic: true
        });

        emit UserRegistered(msg.sender, _name, block.timestamp);
    }

    function updateWeight(uint256 _newWeight) public onlyRegistered {
        UserProfile storage profile = userProfiles[msg.sender];
        
        // Check if they lost 5% or more of their weight
        if (_newWeight < profile.weight && (profile.weight - _newWeight) * 100 / profile.weight >= 5) {
            emit MilestoneAchieved(msg.sender, "Weight Goal Reached", block.timestamp);
        }
        
        profile.weight = _newWeight;
        emit ProfileUpdated(msg.sender, _newWeight, block.timestamp);
    }

    function setProfileVisibility(bool _isPublic) public onlyRegistered{
        isPublicProfile[msg.sender] = _isPublic;
        emit ProfileVisibilityUpdated(msg.sender, _isPublic);
    }

    function logWorkout(string memory _activityType, uint256 _duration, uint256 _distance) public onlyRegistered {
        // Create the workout record
        WorkoutActivity memory newWorkout = WorkoutActivity({
            activityType: _activityType,
            duration: _duration,
            distance: _distance,
            timestamp: block.timestamp,
            caloriesBurned: calculateCalories(_activityType, _duration, userProfiles[msg.sender].weight)
        });

        // Store it and update counters
        workoutHistory[msg.sender].push(newWorkout);
        totalWorkouts[msg.sender]++;
        totalDistance[msg.sender] += _distance;
        totalDuration[msg.sender] += _duration;

        addToGlobalFeed(msg.sender, _activityType, _distance, block.timestamp);

        // Broadcast the workout
        emit WorkoutLogged(msg.sender, _activityType, _duration, _distance, block.timestamp);

        // Check for workout count milestones
        if (totalWorkouts[msg.sender] == 10) {
            emit MilestoneAchieved(msg.sender, "10 Workouts Completed", block.timestamp);
        } else if (totalWorkouts[msg.sender] == 50) {
            emit MilestoneAchieved(msg.sender, "50 Workouts Completed", block.timestamp);
        }

        // Check for distance milestone (100km = 100,000 meters)
        if (totalDistance[msg.sender] >= 100000 && totalDistance[msg.sender] - _distance < 100000) {
            emit MilestoneAchieved(msg.sender, "100K Total Distance", block.timestamp);
        }
    }

    function followUser(address _userToFollow) public onlyRegistered userExists(_userToFollow) notSelf(_userToFollow){
        require(!isFollowing[msg.sender][_userToFollow],"Already following");
        isFollowing[msg.sender][_userToFollow] = true;

        followingList[msg.sender].push(_userToFollow);
        followersList[_userToFollow].push(msg.sender);

        emit followed(msg.sender, _userToFollow, block.timestamp);
    }

    function unfollowUser(address _userToUnfollow) public 
    onlyRegistered 
    userExists(_userToUnfollow)
    notSelf(_userToUnfollow) {
        require(isFollowing[msg.sender][_userToUnfollow],"Not following");

        isFollowing[msg.sender][_userToUnfollow] = false;

        removeFromArray(followingList[msg.sender], _userToUnfollow);
        removeFromArray(followersList[_userToUnfollow], msg.sender);

        emit Unfollowed(msg.sender, _userToUnfollow, block.timestamp);
    }

    function getFollowerCount(address _user) public view userExists(_user) returns (uint256) {
        return followersList[_user].length;
    }
    
    function getFollowingCount(address _user) public view userExists(_user) returns (uint256) {
        return followingList[_user].length;
    }

    function getFollowers(address _user) public view userExists(_user) returns (address[] memory) {
        return followersList[_user];
    }
    
    function getFollowing(address _user) public view userExists(_user) returns (address[] memory) {
        return followingList[_user];
    }

    function getWorkoutHistory(address _user) public view 
        userExists(_user)
        profileIsPublicOrFollowing(_user) 
        returns (WorkoutActivity[] memory) 
    {
        return workoutHistory[_user];
    }

    function getRecentWorkouts(address _user, uint256 _limit) public view 
    userExists(_user)
    profileIsPublicOrFollowing(_user)
    returns(WorkoutActivity[] memory){
        uint256 historyLength = workoutHistory[_user].length;
        uint256 limit = _limit > historyLength ? historyLength : _limit;
        WorkoutActivity[] memory recent = new WorkoutActivity[](limit);

        for(uint256 i=0; i<limit; i++){
           recent[i]= workoutHistory[_user][historyLength - limit +i];
        }
       return recent;
    }

    function compareStats(address _user1, address _user2) public view
      userExists(_user1)
      userExists(_user2)
      returns(
        uint256 user1Workouts,
        uint256 user1Workouts,
        uint256 user2Workouts,
        uint256 user1Distance,
        uint256 user2Distance,
        uint256 user1Duration,
        uint256 user2Duration,
        string memory winnerWorkouts,
        string memory winnerDistance
      ){
        // Check privacy settings
        if (!isPublicProfile[_user1] && !isFollowing[msg.sender][_user1]) {
            return (0, 0, 0, 0, 0, 0, "Private", "Private");
        }
        if (!isPublicProfile[_user2] && !isFollowing[msg.sender][_user2]) {
            return (0, 0, 0, 0, 0, 0, "Private", "Private");
        }

        user1Workouts = totalWorkouts[_user1];
        user2Workouts = totalWorkouts[_user2];
        user1Distance = totalDistance[_user1];
        user2Distance = totalDistance[_user2];
        user1Duration = totalDuration[_user1];
        user2Duration = totalDuration[_user2];

        if (user1Workouts > user2Workouts) {
            winnerWorkouts = userProfiles[_user1].name;
        } else if (user2Workouts > user1Workouts) {
            winnerWorkouts = userProfiles[_user2].name;
        } else {
            winnerWorkouts = "Tie";
        }
        
        if (user1Distance > user2Distance) {
            winnerDistance = userProfiles[_user1].name;
        } else if (user2Distance > user1Distance) {
            winnerDistance = userProfiles[_user2].name;
        } else {
            winnerDistance = "Tie";
        }
      }

      function getGlobalFeed(uint256 _limit) public view returns (ActivityFeed[] memory) {
        uint256 feedLength = globalFeed.length;
        uint256 limit = _limit > feedLength ? feedLength : _limit;
        ActivityFeed[] memory recentFeed = new ActivityFeed[](limit);
        
        for (uint256 i = 0; i < limit; i++) {
            recentFeed[i] = globalFeed[feedLength - limit + i];
        }
        
        return recentFeed;
    }

    function getLeaderboard(uint256 _limit) public view returns(
        address[] memory topUsers,
        uint256[] memory distances,
        uint256[] memory workoutCounts
    ){
        address[] memory registeredUsers = getAllRegisteredUsers();
        uint256 count = registeredUsers.length;


    }

    function getLeaderboard(uint256 _limit) public view returns (
        address[] memory topUsers,
        uint256[] memory distances,
        uint256[] memory workoutCounts
    ) {
        // Collect all registered users
        address[] memory registeredUsers = getAllRegisteredUsers();
        uint256 count = registeredUsers.length;
        
        // Simple bubble sort by distance
        for (uint256 i = 0; i < count - 1; i++) {
            for (uint256 j = 0; j < count - i - 1; j++) {
                if (totalDistance[registeredUsers[j]] < totalDistance[registeredUsers[j + 1]]) {
                    address temp = registeredUsers[j];
                    registeredUsers[j] = registeredUsers[j + 1];
                    registeredUsers[j + 1] = temp;
                }
            }
        }
        
        // Determine limit
        uint256 resultLimit = _limit > count ? count : _limit;
        
        topUsers = new address[](resultLimit);
        distances = new uint256[](resultLimit);
        workoutCounts = new uint256[](resultLimit);
        
        for (uint256 i = 0; i < resultLimit; i++) {
            topUsers[i] = registeredUsers[i];
            distances[i] = totalDistance[registeredUsers[i]];
            workoutCounts[i] = totalWorkouts[registeredUsers[i]];
        }
    }

    function calculateCalories(string memory _activityType, uint256 _duration, uint256 _weight) private pure returns (uint256) {
        // Simple calorie calculation based on activity type
        // MET values: Running ~8.0, Cycling ~7.0, Swimming ~6.0, Walking ~3.5
        uint256 met;
        
        if (keccak256(abi.encodePacked(_activityType)) == keccak256(abi.encodePacked("Running"))) {
            met = 8;
        } else if (keccak256(abi.encodePacked(_activityType)) == keccak256(abi.encodePacked("Cycling"))) {
            met = 7;
        } else if (keccak256(abi.encodePacked(_activityType)) == keccak256(abi.encodePacked("Swimming"))) {
            met = 6;
        } else if (keccak256(abi.encodePacked(_activityType)) == keccak256(abi.encodePacked("Walking"))) {
            met = 3;
        } else {
            met = 5; // Default
        }
        
        // Calories = MET * weight(kg) * duration(hours)
        // duration in seconds converted to hours
        uint256 durationHours = _duration / 3600;
        if (durationHours == 0 && _duration > 0) {
            durationHours = 1; // Minimum 1 hour for calculation
        }
        
        return met * _weight * durationHours;
    }

    function addToGlobalFeed(address _user, string memory _activityType, uint256 _distance, uint256 _timestamp) private {
        // Add new feed item
        ActivityFeed memory newFeed = ActivityFeed({
            userAddress: _user,
            activityType: _activityType, 
            distance: _distance,
            timestamp: _timestamp,
            isWorkout: true
        });
        
        globalFeed.push(newFeed);
        
        // Keep feed size manageable
        if (globalFeed.length > MAX_FEED_SIZE) {
            // Remove oldest entries
            uint256 toRemove = globalFeed.length - MAX_FEED_SIZE;
            for (uint256 i = 0; i < toRemove; i++) {
                delete globalFeed[i];
            }
            // Reorganize array
            uint256 newLength = globalFeed.length - toRemove;
            for (uint256 i = 0; i < newLength; i++) {
                globalFeed[i] = globalFeed[i + toRemove];
            }
            // Delete extra slots
            for (uint256 i = newLength; i < globalFeed.length; i++) {
                delete globalFeed[i];
            }
            globalFeed.length = newLength;
        }
    }

    function removeFromArray(address[] storage _array, address _address) private {
        for (uint256 i = 0; i < _array.length; i++) {
            if (_array[i] == _address) {
                _array[i] = _array[_array.length - 1];
                _array.pop();
                break;
            }
        }
    }
}

// NFT badges sample code => 

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract WorkoutBadges is ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    // Badge types
    enum BadgeType {
        FIRST_WORKOUT,
        TEN_WORKOUTS,
        FIFTY_WORKOUTS,
        HUNDRED_WORKOUTS,
        HUNDRED_KM,
        FIVE_HUNDRED_KM,
        WEIGHT_GOAL
    }

    // Mapping to track which badges a user has
    mapping(address => mapping(BadgeType => bool)) public hasBadge;
    
    // Mapping to track which token ID belongs to which badge
    mapping(address => mapping(BadgeType => uint256)) public badgeTokenId;
    
    // Badge metadata URIs (IPFS or hosted)
    mapping(BadgeType => string) public badgeURI;

    event BadgeMinted(address indexed user, BadgeType badgeType, uint256 tokenId);
    event BadgeURISet(BadgeType badgeType, string uri);

    constructor() ERC721("Workout Badges", "WKB") {
        // Set default badge metadata (replace with actual IPFS hashes)
        setBadgeURI(BadgeType.FIRST_WORKOUT, "ipfs://QmFirstWorkoutBadge");
        setBadgeURI(BadgeType.TEN_WORKOUTS, "ipfs://QmTenWorkoutBadge");
        setBadgeURI(BadgeType.FIFTY_WORKOUTS, "ipfs://QmFiftyWorkoutBadge");
        setBadgeURI(BadgeType.HUNDRED_WORKOUTS, "ipfs://QmHundredWorkoutBadge");
        setBadgeURI(BadgeType.HUNDRED_KM, "ipfs://QmHundredKMBadge");
        setBadgeURI(BadgeType.FIVE_HUNDRED_KM, "ipfs://QmFiveHundredKMBadge");
        setBadgeURI(BadgeType.WEIGHT_GOAL, "ipfs://QmWeightGoalBadge");
    }

    function setBadgeURI(BadgeType _badgeType, string memory _uri) public onlyOwner {
        badgeURI[_badgeType] = _uri;
        emit BadgeURISet(_badgeType, _uri);
    }

    function mintBadge(address _user, BadgeType _badgeType) internal returns (uint256) {
        require(!hasBadge[_user][_badgeType], "Badge already minted for this user");
        
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();
        
        _mint(_user, newTokenId);
        _setTokenURI(newTokenId, badgeURI[_badgeType]);
        
        hasBadge[_user][_badgeType] = true;
        badgeTokenId[_user][_badgeType] = newTokenId;
        
        emit BadgeMinted(_user, _badgeType, newTokenId);
        
        return newTokenId;
    }

    function getUserBadges(address _user) public view returns (BadgeType[] memory) {
        // Count how many badges the user has
        uint256 badgeCount = 0;
        for (uint256 i = 0; i < 7; i++) {
            BadgeType badge = BadgeType(i);
            if (hasBadge[_user][badge]) {
                badgeCount++;
            }
        }
        
        // Create array of badges
        BadgeType[] memory badges = new BadgeType[](badgeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < 7; i++) {
            BadgeType badge = BadgeType(i);
            if (hasBadge[_user][badge]) {
                badges[index] = badge;
                index++;
            }
        }
        
        return badges;
    }

    function getUserBadgeTokenIds(address _user) public view returns (uint256[] memory) {
        BadgeType[] memory badges = getUserBadges(_user);
        uint256[] memory tokenIds = new uint256[](badges.length);
        
        for (uint256 i = 0; i < badges.length; i++) {
            tokenIds[i] = badgeTokenId[_user][badges[i]];
        }
        
        return tokenIds;
    }

    function getBadgeName(BadgeType _badgeType) public pure returns (string memory) {
        if (_badgeType == BadgeType.FIRST_WORKOUT) return "First Workout";
        if (_badgeType == BadgeType.TEN_WORKOUTS) return "10 Workouts";
        if (_badgeType == BadgeType.FIFTY_WORKOUTS) return "50 Workouts";
        if (_badgeType == BadgeType.HUNDRED_WORKOUTS) return "100 Workouts";
        if (_badgeType == BadgeType.HUNDRED_KM) return "100 KM Total";
        if (_badgeType == BadgeType.FIVE_HUNDRED_KM) return "500 KM Total";
        if (_badgeType == BadgeType.WEIGHT_GOAL) return "Weight Goal";
        return "";
    }
}


