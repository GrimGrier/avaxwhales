/*

*/

// SPDX-License-Identifier: Unlicensed
//C U ON THE MOON

pragma solidity ^0.8.4;

interface IDistributor {
    function startDistribution() external;
    function setDistributionParameters(uint256 _minPeriod, uint256 _minDistribution, uint256 _gas) external;
    function setShares(address shareholder, uint256 amount) external;
    function process() external;
    function deposit() external payable;
    function claim(address shareholder) external;
    function getUnpaidRewards(address shareholder) external view returns (uint256);
    function getPaidRewards(address shareholder) external view returns (uint256);
    function getClaimTime(address shareholder) external view returns (uint256);
    function countShareholders() external view returns (uint256);
    function getTotalRewards() external view returns (uint256);
    function getTotalRewarded() external view returns (uint256);
    function migrate(address distributor) external;
}

contract Distributor is IDistributor {
    mapping(address => bool) mainContract;

    struct Share {
        uint256 amount;
        uint256 totalExcluded;
        uint256 totalRealised;
    }

    address[] public shareholders;
    mapping (address => uint256) public shareholderIndexes;
    mapping (address => uint256) public shareholderClaims;

    mapping (address => Share) public shares;

    uint256 public totalShares;
    uint256 public totalRewards;
    uint256 public totalRewarded;
    uint256 public rewardsPerShare;
    uint256 public rewardsPerShareAccuracyFactor = 10 ** 36;

    uint256 public minPeriod = 1 hours;
    uint256 public minDistribution = 1 * (10 ** 15);
    uint256 public gas = 500000;
    
    uint256 currentIndex;
    mapping(address => bool) markets;
    Distributor previous;

    bool public initialized;
    modifier initialization() {
        require(!initialized);
        _;
        initialized = true;
    }

    modifier onlyMain() {
        require(mainContract[msg.sender]); _;
    }

    constructor (address _mainContract, address _market) {
        mainContract[_mainContract] = true;
        mainContract[_market] = true;
    }
        
    function startDistribution() external override initialization onlyMain {
        rewardsPerShare = (rewardsPerShareAccuracyFactor * address(this).balance) / totalShares;
    }
    
    function migrate(address _distributor) external override onlyMain {
        Distributor distributor = Distributor(payable(_distributor));
        require(!distributor.initialized());
        payable(_distributor).transfer(address(this).balance);
    }

    function setDistributionParameters(uint256 _minPeriod, uint256 _minDistribution, uint256 _gas) external override onlyMain {
        minPeriod = _minPeriod;
        minDistribution = _minDistribution;
        gas = _gas;
    }

    function setShares(address shareholder, uint256 amount) external override onlyMain {
        if(amount > 0 && shares[shareholder].amount == 0){
            addShareholder(shareholder);
        }else if(amount == 0 && shares[shareholder].amount > 0){
            removeShareholder(shareholder);
        }
        
        if(shares[shareholder].amount > 0){
            distributeDividend(shareholder);
        }
        
        totalShares = (totalShares - shares[shareholder].amount) + amount;
        shares[shareholder].amount = amount;
        
        shares[shareholder].totalExcluded = getCumulativeDividends(amount);
    }

    function deposit() external override payable {
        totalRewards = totalRewards + msg.value;
        if(initialized)
            rewardsPerShare = rewardsPerShare + (rewardsPerShareAccuracyFactor * msg.value) / totalShares;
    }

    function process() public override onlyMain {
        uint256 shareholderCount = shareholders.length;

        if(shareholderCount == 0) { return; }

        uint256 gasUsed = 0;
        uint256 gasLeft = gasleft();

        uint256 iterations = 0;

        while(gasUsed < gas && iterations < shareholderCount) {
            if(currentIndex >= shareholderCount){
                currentIndex = 0;
            }
            
            if(shouldDistribute(shareholders[currentIndex])){
                distributeDividend(shareholders[currentIndex]);
            }

            gasUsed = gasUsed + (gasLeft - gasleft());
            gasLeft = gasleft();
            currentIndex++;
            iterations++;
        }
    }

    function shouldDistribute(address shareholder) internal view returns (bool) {
        return shareholderClaims[shareholder] + minPeriod < block.timestamp
                && getUnpaidRewards(shareholder) > minDistribution;
    }
    
    function getClaimTime(address shareholder) external view override returns (uint256) {
        if (shareholderClaims[shareholder] + minPeriod <= block.timestamp)
            return 0;
        else
            return (shareholderClaims[shareholder] + minPeriod) - block.timestamp;
    }

    function distributeDividend(address shareholder) internal {
        if(shares[shareholder].amount == 0){ return; }
        
        uint256 unpaidEarnings = getUnpaidRewards(shareholder);
        if(unpaidEarnings > 0){
            totalRewarded = totalRewarded + unpaidEarnings;
            shareholderClaims[shareholder] = block.timestamp;
            shares[shareholder].totalRealised = shares[shareholder].totalRealised + unpaidEarnings;
            shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
            payable(shareholder).transfer(unpaidEarnings);
        }
    }

    function claim(address shareholder) external override onlyMain {
        distributeDividend(shareholder);
    }

    function getUnpaidRewards(address shareholder) public view override returns (uint256) {
        if(shares[shareholder].amount == 0){ return 0; }

        uint256 shareholderTotalDividends = getCumulativeDividends(shares[shareholder].amount);
        uint256 shareholderTotalExcluded = shares[shareholder].totalExcluded;

        if(shareholderTotalDividends <= shareholderTotalExcluded){ return 0; }

        return shareholderTotalDividends - shareholderTotalExcluded;
    }
    
    function getPaidRewards(address shareholder) external view override returns (uint256) {
        return shares[shareholder].totalRealised;
    }

    function getCumulativeDividends(uint256 share) internal view returns (uint256) {
        if(share == 0){ return 0; }
        return (share * rewardsPerShare) / rewardsPerShareAccuracyFactor;
    }
    
    function countShareholders() external view override returns (uint256) {
        return shareholders.length;
    }
    
    function getTotalRewards() external view override returns (uint256) {
        return totalRewards;
    }
    function getTotalRewarded() external view override returns (uint256) {
        return totalRewarded;
    }

    function addShareholder(address shareholder) internal {
        shareholderIndexes[shareholder] = shareholders.length;
        shareholders.push(shareholder);
    }

    function removeShareholder(address shareholder) internal {
        shareholders[shareholderIndexes[shareholder]] = shareholders[shareholders.length-1];
        shareholderIndexes[shareholders[shareholders.length-1]] = shareholderIndexes[shareholder];
        shareholders.pop();
    }
    receive() external payable { }
}
