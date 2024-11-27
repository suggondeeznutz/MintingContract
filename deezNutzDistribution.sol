// SPDX-License-Identifier: GPL
pragma solidity 0.8.26;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// Declare the ContractConnecter interface
interface ContractConnecter {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint256);
}

/// @title SuggonDeeznutz Distribution Contract
/// @author Modified from Professor Suggon Deeznutz
/// @notice The SuggonDeeznutz distribution contract governs the distribution of pre-minted SuggonDeeznutz Token based on the tiered distribution rules. 
/// @dev This is the distribution contract of the SuggonDeeznutz platform. It contains the Nutz token distribution logic. 
contract DeeznutzDistribution is ReentrancyGuard {

    /// Authorative contracts for the SuggonDeeznutz Platform
    address public admin;               // contract that may update foundation and nutz token addresses
    address public distributionContract;     // this contract address
    address public foundation;          // Deeznutz foundation address that will recieve ether from distribution and validate/produce NFTs in the future
    address public nutzToken;           // contract address for the nutz token itself
    uint256 public currentNutzCost;     // cost of nutz for the current distribution tier/what they cost now
    uint256 public finalDistributionBlock;      // block number which will be used for the snapshot for NFT distribution
    uint256 immutable public blockDelay = 90000;             // security block delay for critical updates like changing admin or foundation address
    uint256 immutable public maxNutz = 69_000_000_000;       // max amount of nutz that will be distributed in whole number (not wei)
    uint256 immutable public tierPercentIncrease = 11337;    // amount each tier increases the cost of nutz, divided by the tierPerentDecimal value
    uint256 immutable public tierPercentDecimal = 1e4;       // creates price increase for each tier in combination with above tierPercentIncrease value
    uint256 immutable public tierZeroCost = 33000000;        // initial cost of nutz for tier 0 in wei
    uint256 immutable public nutzPerTier = 1_000_000_000;    // amount of nutz in each distribution tier
    mapping(address => uint256) public foundationContractUpdateDelay;  // implements a block based delay for extra security on critical variable updates
    mapping(address => uint256) public adminContractUpdateDelay;       // implements a block based delay for extra security on critical variable updates

    struct DistributionState {
        uint96 currentTier;
        uint160 distributedNutz;
    }
    DistributionState public distributionState;

    /// @notice ContractUpdateRequested event is emitted as notification that one of the address variables will be updated to the address in this events data
    /// @param newContract This is the new address that one of the main contract variables will be updated to once current block reaches the delayToBlock number
    /// @param delayToBlock After current block has passed this number, the admin or foundation contract may be updated to this address
    /// @param typeOf The contract variable type that will be updated
    event ContractUpdateRequested(address newContract, uint256 delayToBlock, string typeOf);
    
    /// @notice ContractUpdated event is emitted when one of the address variables has been updated to the address in this events data
    /// @param contractName This is the name of the variable that has been updated; admin or foundation
    /// @param newContract This is the new address the variable has been updated to
    event ContractUpdated(string contractName, address newContract);
    
    /// @notice nutzDistributed event is emitted when nutz are successfully distributed
    /// @param buyer address
    /// @param amount distributed
    event nutzDistributed(address buyer, uint256 amount);

    /// @notice nutzTokenContractSet event is emitted when the nutz token address is set
    /// @param nutzTokenAddress address of the nutz token contract
    event nutzTokenContractSet(address nutzTokenAddress); 
    
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call");
        _;
    }

    constructor() {
        admin = msg.sender;                 // can be updated to multi-sig address later as needed
        foundation = msg.sender;            // can be updated to multi-sig address later as needed
        distributionContract = address(this);  
        currentNutzCost = tierZeroCost;     // set current cost to tier 0/initial nutz cost
        nutzToken = address(0);             // update this once nutz token contract is created
        distributionState.distributedNutz = 0;          // initiate distributedNutz         
        distributionState.currentTier = 0;              // initiate at tier 0
        finalDistributionBlock = 0;                 // final block will be updated when distribution is completed (distributedNutz = maxNutz)
    }

    /// @notice Requests/approves a contract address for updating the admin contract variables, after a time delay for safety
    /// @dev Contacts must be added to a mapping via this function in order to pass a block number based time delay for updating the contract addresses
    /// @param _newContract The new address
    function requestUpdateAdminContract(address _newContract) external onlyAdmin {
        require(_newContract != address(0),"Address not valid");
        uint256 delayBlock = block.number + blockDelay;
        adminContractUpdateDelay[_newContract] = delayBlock;
        emit ContractUpdateRequested(_newContract,delayBlock,"admin");
    }

    /// @notice Update link to the Deeznutz admin contract
    /// @dev This setting determines access to the address updating functions
    /// @param _newAdminContract The new address
    function updateAdminContract(address _newAdminContract) external onlyAdmin {
        require(_newAdminContract != address(0),"Address not valid");
        require(adminContractUpdateDelay[_newAdminContract] > 0,"Update not requested");
        require(adminContractUpdateDelay[_newAdminContract] < block.number,"Delay not reached");     
        admin = _newAdminContract;
        adminContractUpdateDelay[_newAdminContract] = 0;
        emit ContractUpdated("admin",_newAdminContract);
    }

    /// @notice Requests/approves a contract address for updating foundation contract variable, after a time delay for safety
    /// @dev Contacts must be added to a mapping via this function in order to pass a block number based time delay for updating the contract addresses
    /// @param _newContract The new address
    function requestUpdateFoundationContract(address _newContract) external onlyAdmin {
        require(_newContract != address(0),"Address not valid");
        uint256 delayBlock = block.number + blockDelay;
        foundationContractUpdateDelay[_newContract] = delayBlock;
        emit ContractUpdateRequested(_newContract,delayBlock,"foundation");
    }

    /// @notice Update the Deeznutz foundation contract
    /// @dev Contacts must be added to a mapping via this function in order to pass a block number based time delay for updating the contract addresses
    /// @param _newFoundationContract The new address
    function updateFoundationContract(address _newFoundationContract) external onlyAdmin {
        require(_newFoundationContract != address(0),"Address");
        require(foundationContractUpdateDelay[_newFoundationContract] > 0,"Update not requested");
        require(foundationContractUpdateDelay[_newFoundationContract] < block.number,"Delay not reached"); 
        require(_newFoundationContract != address(distributionContract),"Distribution Address");        
        foundation = _newFoundationContract;
        foundationContractUpdateDelay[_newFoundationContract] = 0;
        emit ContractUpdated("foundation",_newFoundationContract);
    }
    
    /// @notice Update link to the SuggonDeeznutz token contract
    /// @dev This setting connects the token contract and the distribution contract, it may only be updated by the admin address before distribution has commenced
    /// @param _nutzTokenContract The new address
  function updateNutzTokenContract(address _nutzTokenContract) external onlyAdmin {
        require(_nutzTokenContract != address(0),"Address not valid");
        require(distributionState.distributedNutz == 0,"Distribution Already Started");
        // Verify the contract has the full balance
        uint256 decimals = ContractConnecter(_nutzTokenContract).decimals();
        uint256 balance = ContractConnecter(_nutzTokenContract).balanceOf(address(this));
        require(balance == maxNutz * (10 ** decimals), "Insufficient token balance");
        nutzToken = _nutzTokenContract;
        emit nutzTokenContractSet(_nutzTokenContract);
    }

    /// @notice Distributes some Nutz  
    /// @dev Transfers Nutz for Ether input with the transaction, emits events and updates variables as necessary to keep track of progress. Max of 3billion nutz may be distributed in one transaction. Has various protections to prevent reentrancies and over distribution and returns any excess Ether to the sender along with Nutz. 
    receive() external payable nonReentrant {
        require(msg.value > 0, "No Ether sent");
        require(nutzToken != address(0), "Nutz token not set");

        DistributionState memory state = distributionState;        
        require(state.distributedNutz < maxNutz,"All Nutz distributed!");
        
        uint256 price = currentNutzCost; // Local cache

        uint256 decimals = ContractConnecter(nutzToken).decimals();
        
        uint256 maxTiers = maxNutz / nutzPerTier;
        require(state.currentTier < maxTiers,"Current Tier can not exceed maxTiers");        
        uint256 _distributeAmount = 0;
        uint256 _totalCost = 0;
        uint256 _tiersTraversed = 0;
        
        while (msg.value > _totalCost && state.currentTier < maxTiers && _tiersTraversed < 3) {
            uint256 remainingNutzInTier = (nutzPerTier * (state.currentTier + 1)) - state.distributedNutz - _distributeAmount;
            uint256 tierCost = remainingNutzInTier * price;
            
            if (msg.value - _totalCost >= tierCost) {
                _distributeAmount += remainingNutzInTier;
                _totalCost += tierCost;
                
                // Critical state updates must happen immediately
                state.currentTier++;
                price = (price * tierPercentIncrease) / tierPercentDecimal;
                currentNutzCost = price;
                _tiersTraversed++;
            } else {
                uint256 remainingEther = msg.value - _totalCost;
                uint256 additionalNutz = remainingEther / price;
                _distributeAmount += additionalNutz;
                _totalCost += additionalNutz * price;
                break;
            }
        }        

        require(state.distributedNutz + _distributeAmount <= maxNutz,"Final Check Max Nutz");

        // Transfer tokens instead of minting
        bool success = ContractConnecter(nutzToken).transfer(
            msg.sender, 
            _distributeAmount * (10 ** decimals)
        );
        require(success, "Token transfer failed");
                
        // Update final state - do this directly in storage since need type conversion
        distributionState.distributedNutz = uint160(uint256(state.distributedNutz) + _distributeAmount);
        distributionState.currentTier = state.currentTier;

        if (state.distributedNutz + _distributeAmount == maxNutz) {
            finalDistributionBlock = block.number;  // Record the block number of the final distribution
        }

        emit nutzDistributed(msg.sender,_distributeAmount);

        // Refund any remaining Ether back to the sender
        uint256 refundAmount = msg.value - _totalCost;
        if (refundAmount > 0) {
            (bool refundSuccess, ) = msg.sender.call{value: refundAmount}("");
            require(refundSuccess, "Refund failed");
        }
    }

    /// @notice Transfers the accumulated Ether to the foundation address.
    /// @dev This function can only be called by the admin.
    function transferToFoundation() external onlyAdmin nonReentrant {
        require(address(this).balance > 0, "No Ether to transfer");
        (bool sent, ) = foundation.call{value: address(this).balance}("");
        require(sent, "Failed to transfer Ether to foundation");
    }

    function distributedNutz() external view returns (uint160) {
        return distributionState.distributedNutz;
    }

    function currentTier() external view returns (uint96) {
        return distributionState.currentTier;
    }
}