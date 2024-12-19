// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract AutheoRewardDistribution is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // Token configuration
    IERC20 public immutable Autheo;
    uint256 public immutable totalSupply;

    // Constants for decimal handling
    uint256 private immutable SCALE = 10 ** 18;

    // Allocation percentages (scaled by DECIMALS)
    uint256 public constant BUG_BOUNTY_ALLOCATION_PERCENTAGE = 3000; // 30%  of total supply
    uint256 public constant DAPP_REWARD_ALLOCATION_PERCENTAGE = 200; // 2%  of total supply
    uint256 public constant DEVELOPER_REWARD_ALLOCATION_PERCENTAGE = 100; // 1%  of total supply
    uint256 private constant MAX_BPS = 10000;

    // Fixed reward amounts
    uint256 public immutable MONTHLY_DAPP_REWARD = 5000 * SCALE;
    uint256 public immutable MONTHLY_UPTIME_BONUS = 500 * SCALE;
    uint256 public immutable DEVELOPER_DEPLOYMENT_REWARD = 1500 * SCALE;

    // Testnet period
    uint256 public constant TESTNET_PERIOD = 90 days;
    uint256 public immutable testnetStartTime;

    // Claim amounts
    uint256 public claimPerContractDeployer;
    uint256 public claimPerDappUser;

    // Tracking variables
    uint256 public totalDappRewardsIds;
    uint256 public totalDappRewardsClaimed;
    uint256 public totalContractDeploymentClaimed;

    // Bug bounty reward calculations
    uint256 public lowRewardPerUser;
    uint256 public mediumRewardPerUser;
    uint256 public highRewardPerUser;

    uint256 public totalBugBountyRewardsClaimed;
    // Constants for reward percentages
    uint256 public constant LOW_PERCENTAGE = 500;
    uint256 public constant MEDIUM_PERCENTAGE = 3500;
    uint256 public constant HIGH_PERCENTAGE = 6000;

    // User registration arrays
    address[] public lowBugBountyUsers;
    address[] public mediumBugBountyUsers;
    address[] public highBugBountyUsers;
    address[] public whitelistedContractDeploymentUsers;
    address[] public whitelistedDappRewardUsers;

    address[] public allUsers;

    uint256 public dappUserCurrentId;

    // Mapping to track bug bounty criticality for users
    mapping(address => bool) public isWhitelistedContractDeploymentUsers;
    mapping(address => mapping(uint256 => bool))
        public isWhitelistedDappUsersForId;

    mapping(address => bool) public isContractDeploymentUsersClaimed;
    // mapping(address => bool) public isDappUsersClaimedForId;
    mapping(address => bool) public isWhitelistedDappUsers;
    mapping(address => bool) public isDappUsersClaimed;
    mapping(address => bool) public isBugBountyUsersClaimed;
    mapping(address => bool) public hasGoodUptime;
    mapping(address => mapping(uint256 => bool)) public hasClaimedForID;
    mapping(address => BugCriticality) public bugBountyCriticality;

    mapping(address => bool) public hasReward;
    mapping(address => bool) public isDistributed;

    // Bug Criticality Enum
    enum BugCriticality {
        NONE,
        LOW,
        MEDIUM,
        HIGH
    }

    // Events
    event WhitelistUpdated(string claimType, address indexed user, bool status);
    event Claimed(string claimType, address indexed user, uint256 time);
    event ClaimAmountUpdated(uint256 newClaimedAmount);
    event EmergencyWithdraw(address token, uint256 amount);

    error USER_HAS_NO_CLAIM(address user);

    // Modifiers
    modifier onlyDuringTestnet() {
        require(
            block.timestamp <= testnetStartTime + TESTNET_PERIOD,
            "Not in testnet period"
        );
        _;
    }

    modifier onlyAfterTestnet() {
        require(
            block.timestamp > testnetStartTime + TESTNET_PERIOD,
            "Still in testnet period"
        );
        _;
    }

    /**
     * @dev Constructor
     * @param _tokenAddress Address of the ERC20 token contract
     */
    constructor(address _tokenAddress, uint256 _stratTime, address _initialAddress) Ownable(_initialAddress) {
        require(_tokenAddress != address(0), "Invalid token address");
        require(_stratTime > block.timestamp, "Invalid start time");
        Autheo = IERC20(_tokenAddress);
        testnetStartTime = _stratTime;
        totalSupply = Autheo.totalSupply();
    }

    function setClaimPerContractDeployer(
        uint256 _claimAmount
    ) public onlyOwner {
        // only owner should claim
        claimPerContractDeployer = _claimAmount;

        emit ClaimAmountUpdated(_claimAmount);
    }

    function setClaimPerDappUser(uint256 _claimAmount) public onlyOwner {
        // only owner should claim
        claimPerDappUser = _claimAmount;
        emit ClaimAmountUpdated(_claimAmount);
    }

    /**
     * @dev Register low criticality bug bounty users
     * @param _lowBugBountyUsers Array of addresses for low criticality bug bounties
     */
    function registerLowBugBountyUsers(
        address[] memory _lowBugBountyUsers
    ) external onlyOwner {
        uint256 totalBugBountyAllocation = (totalSupply *
            BUG_BOUNTY_ALLOCATION_PERCENTAGE) / MAX_BPS;

        lowRewardPerUser =
            ((totalBugBountyAllocation * LOW_PERCENTAGE) / 10000) /
            _lowBugBountyUsers.length;

        for (uint256 i = 0; i < _lowBugBountyUsers.length; ) {
            address user = _lowBugBountyUsers[i];

            require(user != address(0), "Invalid address");
            require(
                bugBountyCriticality[user] == BugCriticality.NONE,
                "User already assigned to a criticality"
            );
            if (!hasReward[user]) {
                allUsers.push(user);
            }
            bugBountyCriticality[user] = BugCriticality.LOW;
            hasReward[user] = true;
            lowBugBountyUsers.push(user);
            emit WhitelistUpdated("Low Bug Bounty", user, true);

            unchecked {
                i++;
            }
        }
    }

    /**
     * @dev Register medium criticality bug bounty users
     * @param _mediumBugBountyUsers Array of addresses for medium criticality bug bounties
     */
    function registerMediumBugBountyUsers(
        address[] memory _mediumBugBountyUsers
    ) external onlyOwner {
        uint256 totalBugBountyAllocation = (totalSupply *
            BUG_BOUNTY_ALLOCATION_PERCENTAGE) / MAX_BPS;

        mediumRewardPerUser =
            ((totalBugBountyAllocation * MEDIUM_PERCENTAGE) / 100) /
            _mediumBugBountyUsers.length;

        for (uint256 i = 0; i < _mediumBugBountyUsers.length; ) {
            address user = _mediumBugBountyUsers[i];

            require(user != address(0), "Invalid address");
            require(
                bugBountyCriticality[user] == BugCriticality.NONE,
                "User already assigned to a criticality"
            );
            if (!hasReward[user]) {
                allUsers.push(user);
            }

            bugBountyCriticality[user] = BugCriticality.MEDIUM;
            hasReward[user] = true;
            mediumBugBountyUsers.push(user);
            emit WhitelistUpdated("Medium Bug Bounty", user, true);

            unchecked {
                i++;
            }
        }
    }

    /**
     * @dev Register high criticality bug bounty users
     * @param _highBugBountyUsers Array of addresses for high criticality bug bounties
     */
    function registerHighBugBountyUsers(
        address[] memory _highBugBountyUsers
    ) external onlyOwner {
        uint256 totalBugBountyAllocation = (totalSupply *
            BUG_BOUNTY_ALLOCATION_PERCENTAGE) / MAX_BPS;

        highRewardPerUser =
            ((totalBugBountyAllocation * HIGH_PERCENTAGE) / 100) /
            _highBugBountyUsers.length;

        for (uint256 i = 0; i < _highBugBountyUsers.length; ) {
            address user = _highBugBountyUsers[i];

            require(user != address(0), "Invalid address");
            require(
                bugBountyCriticality[user] == BugCriticality.NONE,
                "User already assigned to a criticality"
            );
            if (!hasReward[user]) {
                allUsers.push(user);
            }
            bugBountyCriticality[user] = BugCriticality.HIGH;
            hasReward[user] = true;
            highBugBountyUsers.push(user);
            emit WhitelistUpdated("High Bug Bounty", user, true);

            unchecked {
                i++;
            }
        }
    }

    function registerContractDeploymentUsers(
        address[] memory _contractDeploymentUsers
    ) external onlyOwner {
        uint256 _contractDeploymentUsersLength = _contractDeploymentUsers
            .length;

        require(
            _contractDeploymentUsersLength > 0,
            "Empty contract deployment users array"
        );

        for (uint256 i = 0; i < _contractDeploymentUsersLength; ) {
            address user = _contractDeploymentUsers[i];

            require(user != address(0), "Invalid contract deployment address");
            require(
                !isWhitelistedContractDeploymentUsers[user],
                "Already whitelisted for contract deployment"
            );
            if (!hasReward[user]) {
                allUsers.push(user);
            }

            isWhitelistedContractDeploymentUsers[user] = true;
            hasReward[user] = true;
            whitelistedContractDeploymentUsers.push(user);

            emit WhitelistUpdated("Contract Deployment", user, true);

            unchecked {
                i++;
            }
        }
    }

    function registerDappUsers(
        address[] memory _dappRewardsUsers,
        bool[] memory _userUptime
    ) external onlyOwner {
        uint256 _dappRewardsUsersLength = _dappRewardsUsers.length;
        require(
            _userUptime.length == _dappRewardsUsersLength,
            "Users must be equal length"
        );
        dappUserCurrentId++;

        require(_dappRewardsUsersLength > 0, "Empty dapp rewards users array");

        for (uint256 i = 0; i < _dappRewardsUsersLength; i++) {
            address user = _dappRewardsUsers[i];

            require(user != address(0), "Invalid dapp rewards address");
            require(
                !isWhitelistedDappUsersForId[user][dappUserCurrentId],
                "Dapp user already registered"
            );
            if (_userUptime[i]) {
                hasGoodUptime[user] = true;
            }

            if (!hasReward[user]) {
                allUsers.push(user);
            }

            isWhitelistedDappUsersForId[user][dappUserCurrentId] = true;
            hasReward[user] = true;
            whitelistedDappRewardUsers.push(user);

            emit WhitelistUpdated("Dapp Users", user, true);
        }
    }

    /**
     * @dev Claim rewards for whitelisted address
     */
    function claimReward(
        bool _contractDeploymentClaim,
        bool _bugBountyClaim
    ) external nonReentrant whenNotPaused {
        if (_contractDeploymentClaim) {
            __contractDeploymentClaim(msg.sender);
        } else if (_bugBountyClaim) {
            __bugBountyClaim(msg.sender);
        } else {
            revert USER_HAS_NO_CLAIM(msg.sender);
        }
    }

    function __bugBountyClaim(address _user) private {
        // Implement bug bounty claim logic
        BugCriticality userCriticality = bugBountyCriticality[_user];
        require(userCriticality != BugCriticality.NONE, "No bug bounty reward");

        uint256 rewardAmount;

        // Reset criticality after claim to prevent double-claiming
        bugBountyCriticality[_user] = BugCriticality.NONE;

        // Calculation similar to registerBugBountyClaim
        if (userCriticality == BugCriticality.LOW) {
            rewardAmount = lowRewardPerUser;
        } else if (userCriticality == BugCriticality.MEDIUM) {
            rewardAmount = mediumRewardPerUser;
        } else if (userCriticality == BugCriticality.HIGH) {
            rewardAmount = highRewardPerUser;
        }

        // Check if user has claimed before
        require(
            !isBugBountyUsersClaimed[_user],
            "User already claimed rewards"
        );

        // Track claim
        totalBugBountyRewardsClaimed += rewardAmount;

        // Transfer the amount to user
        Autheo.safeTransfer(_user, rewardAmount);

        emit Claimed("Bug Bounty", _user, block.timestamp);
    }

    function __contractDeploymentClaim(address _user) private {
        // Check if user is whitelisted for one-time deployment claim
        require(isWhitelistedContractDeploymentUsers[_user], "No reward yet");

        // Add timeline checks here
        require(
            block.timestamp < testnetStartTime + TESTNET_PERIOD,
            "Claim time out"
        );

        // Check if user has claimed
        require(
            !isContractDeploymentUsersClaimed[_user],
            "User already claimed rewards"
        );

        // Reset user's claim to true
        isContractDeploymentUsersClaimed[_user] = true;

        // Track claim
        totalContractDeploymentClaimed += claimPerContractDeployer;

        // Transfer the amount to user
        Autheo.safeTransfer(_user, claimPerContractDeployer);

        // Emit an event
        emit Claimed("Contract Deployment", _user, block.timestamp);
    }

    function claimDappRewards(uint256 _id) external nonReentrant whenNotPaused {
        // Ensure that the address is a registered DApp user
        require(
            isWhitelistedDappUsersForId[msg.sender][_id],
            "Not a registered Dapp user"
        );

        // Ensure the user hasn't claimed this month's rewards already
        require(
            !hasClaimedForID[msg.sender][_id],
            "Already claimed rewards for this month"
        );

        uint256 rewardAmount = MONTHLY_DAPP_REWARD;

        // If uptime is good, award the bonus
        if (hasGoodUptime[msg.sender]) {
            rewardAmount += MONTHLY_UPTIME_BONUS;
        }

        // Mark the user as having claimed their rewards for this month
        hasClaimedForID[msg.sender][_id] = true;
        totalDappRewardsClaimed += rewardAmount;

        // Transfer the calculated reward to the user
        Autheo.safeTransfer(msg.sender, rewardAmount);

        // Emit an event for claiming rewards
        emit Claimed("DApp Rewards", msg.sender, block.timestamp);
    }

    /**
     * @dev Calculate remaining bug bounty rewards for each criticality level
     */
    function calculateRemainingClaimedAmount() public view returns (uint256) {
        return (totalBugBountyRewardsClaimed +
            totalContractDeploymentClaimed +
            totalDappRewardsClaimed);
    }

    /**
     * @dev Retrieve all whitelisted contract deployment users
     * @return address[] Array of whitelisted addresses
     */
    function getWhitelistedContractDeploymentUsers()
        external
        view
        returns (address[] memory)
    {
        return whitelistedContractDeploymentUsers;
    }

    /**
     * @dev Calculate remaining contract deployment rewards allocation
     * @notice Returns the amount of tokens still available for contract deployment rewards
     * @return uint256 The remaining amount of tokens available for contract deployment distribution
     */
    function calculateRemainingContractDeploymentReward()
        public
        view
        returns (uint256)
    {
        // calculate total allocation for contract deployment rewards (0.1 of total supply)
        uint256 totalDeploymentAllocation = (totalSupply *
            DEVELOPER_REWARD_ALLOCATION_PERCENTAGE) / MAX_BPS;

        // Return 0 if all rewards have been claimed

        if (totalContractDeploymentClaimed >= totalDeploymentAllocation) {
            return 0;
        }

        return totalDeploymentAllocation - totalContractDeploymentClaimed;
    }

    /**
     * @dev Retrieve all whitelisted dApp reward users
     * @return address[] Array of whitelisted addresses
     */
    function getWhitelistedDappRewardUsers()
        external
        view
        returns (address[] memory)
    {
        return whitelistedDappRewardUsers;
    }

    /**
     * @dev Emergency withdraw any accidentally sent tokens
     * @param token Address of token to withdraw
     */
    function emergencyWithdraw(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No balance to withdraw");

        IERC20(token).safeTransfer(owner(), balance);
        emit EmergencyWithdraw(token, balance);
    }

    /**
     * @dev Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Calculate remaining dApp rewards allocation
     */
    function calculateRemainingDappRewards() public view returns (uint256) {
        // get the percentage of Dapp rewards from total supply
        uint256 totalDappAllocation = (totalSupply *
            DAPP_REWARD_ALLOCATION_PERCENTAGE) / MAX_BPS;
        // substite amount claimed from this percentage and return it
        if (totalDappRewardsClaimed >= totalDappAllocation) {
            return 0;
        }

        return totalDappAllocation - totalDappRewardsClaimed;
    }

    function getAllUsers() external view returns (address[] memory) {
        return allUsers;
    }

    /**
     * @dev Distribute remaining tokens equally among all participants
     */
    function distributeRemainingTokens() external nonReentrant onlyAfterTestnet {
        // Calculate remaining bug bounty rewards
        require(hasReward[msg.sender], "No reward for user");
        require(!isDistributed[msg.sender], "already distributed");
        uint256 totalClaimedAmount = calculateRemainingClaimedAmount();
        uint256 totalAllocationPercent = (BUG_BOUNTY_ALLOCATION_PERCENTAGE +
            DAPP_REWARD_ALLOCATION_PERCENTAGE +
            DEVELOPER_REWARD_ALLOCATION_PERCENTAGE);

        uint256 totalRewards = (totalSupply * totalAllocationPercent) / MAX_BPS;
        require (totalRewards >= totalClaimedAmount, "No reward");

        uint256 availableRewardsToShare = totalRewards - totalClaimedAmount;
        require(
            Autheo.balanceOf(address(this)) >= availableRewardsToShare,
            "Contract doesnt have rewards for users"
        );

        isDistributed[msg.sender] = true;

        uint256 allUsersLength = allUsers.length;

        uint256 equalShares = availableRewardsToShare / allUsersLength;

        Autheo.transfer(msg.sender, equalShares);

        emit Claimed(
            "Remaining Tokens Distributed",
            msg.sender,
            block.timestamp
        );
    }
}
