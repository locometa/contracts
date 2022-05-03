// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20CappedUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";

import "./ERC20.sol";
import "./Pancakeswap.sol";

contract LocoMeta is 
    Initializable, ERC20Upgradeable, ERC20PermitUpgradeable, 
    ERC20CappedUpgradeable, ERC20BurnableUpgradeable,
    OwnableUpgradeable, AccessControlUpgradeable {

  using SafeMathUpgradeable for uint256;
 
  bool private initialized;

  IPancakeSwapV2Router02 private PancakeSwapV2Router;
  address private PancakeSwapV2Pair;

  bytes32 private constant OPMAR_ROLE = 0x0000000000000000000000000000000000000000000000000000000000000001;
  bytes32 private constant SWAPPING_ROLE = 0x0000000000000000000000000000000000000000000000000000000000000010;
  bytes32 private constant BLACKLIST_ROLE = 0x0000000000000000000000000000000000000000000000000000000000000100;

  bool projectInitialized;
 
  uint256 public swapThreshold;
  bool public swapEnabled;

  bool dumpProtectionEnabled;
  bool sniperTax;
  bool tierTaxEnabled;
  bool tradingEnabled;
  bool inSwap;

  uint256 public buyTax;
  uint256 public sellTax;
  uint256 public transferTax;

  uint256 public liquidityShare;
  uint256 public marketingShare;
  uint256 constant TAX_DENOMINATOR=100;
  uint256 totalShares;

  uint256 public transferGas;
  uint256 public launchTime;
  uint256 public total_locked_amount;

  address marketingWallet;

  mapping (address => Locks[]) private _locks;
  mapping (address => bool) public isWhitelisted;
  mapping (address => bool) public isCEX;
  mapping (address => bool) public isMarketMaker;
  mapping (address => bool) public teamMember;

  event ProjectInitialized(bool completed);
  event Bought(address account, uint256 amount);
  event Locked(address account, uint256 amount);
  event Released(address account, uint256 amount);
  event DisableDumpProtection();
  event EnableTrading();
  event SniperTaxRemoved();
  event TriggerSwapBack();
  event RecoverBNB(uint256 amount);
  event RecoverBEP20(address indexed token, uint256 amount);
  event UpdateMarketingWallet(address newWallet, address oldWallet);
  event UpdateGasForProcessing(uint256 indexed newValue, uint256 indexed oldValue);
  event SetWhitelisted(address indexed account, bool indexed status);
  event SetCEX(address indexed account, bool indexed exempt);
  event SetMarketMaker(address indexed account, bool indexed isMM);
  event SetTaxes(uint256 buy, uint256 sell, uint256 transfer);
  event SetShares(uint256 liquidityShare, uint256 marketingShare);
  event SetSwapBackSettings(bool enabled, uint256 amount);
  event ReleaseBudget(uint256 budget, uint256 amount);
  event AutoLiquidity(uint256 PancakeSwapV2Pair, uint256 tokens);
  event DepositOperational(address indexed wallet, uint256 amount);
  event DepositMarketing(address indexed wallet, uint256 amount);
  event DepositRewards(address indexed wallet, uint256 amount);
  event SetTransferGas(uint256 newValue);
  event Swapped();

  struct Locks {
    uint256 identifier;  
    uint256 locked;
    uint256 release_time;
    bool released;
  }

  modifier swapping() {
    inSwap = true;
    _;
    inSwap = false;
  }

  function initialize(
    string memory _name, 
    string memory _symbol,
    uint256 _cap
    ) public initializer {
      require(!initialized, "initialized");
      __ERC20_init(_name, _symbol);
      __ERC20Permit_init(_name);
      __ERC20Capped_init(_cap);
      __ERC20Burnable_init();
      __Ownable_init();
      __AccessControl_init();
      _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
      swapThreshold = 5000 * 10**decimals();
      swapEnabled = true;
      dumpProtectionEnabled = true;
      sniperTax = true;
      buyTax = 9;
      sellTax = 11;
      transferTax = 0;
      liquidityShare = 35;
      marketingShare = 65;
      totalShares = 100;
      transferGas = 30000;
      total_locked_amount = 0;
      initialized = true;
      marketingWallet = address(0x23AB006459B8A8d2539d1C405f0F47dca9B14C9C);
      _mint(address(0x7bB941070e400468f00C39537C76B81E4a805e02), 250000 * 10**18);
    }

    receive() external payable {}

    function _mint(address account, uint256 amount) internal virtual override(ERC20Upgradeable, ERC20CappedUpgradeable) {
      ERC20CappedUpgradeable._mint(account, amount);
    }

    function _revokeRole(bytes32 role, address account) internal virtual override {
        require(msg.sender == owner(),"permErr");
        super._revokeRole(role,account);
    }

    function initializeProject() external onlyOwner {
        require(!projectInitialized);

        // MN: 0x10ED43C718714eb63d5aA57B78B54704E256024E
        // TN: 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3

        IPancakeSwapV2Router02 _pancakeSwapV2Router = IPancakeSwapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        address _pancakeSwapV2Pair = IPancakeSwapV2Factory(_pancakeSwapV2Router.factory())
        .createPair(address(this), _pancakeSwapV2Router.WETH());

        PancakeSwapV2Router = _pancakeSwapV2Router;
        PancakeSwapV2Pair = _pancakeSwapV2Pair;

        _approve(address(this), address(PancakeSwapV2Router), type(uint256).max);

        isMarketMaker[PancakeSwapV2Pair] = true;
        isWhitelisted[owner()] = true;
        projectInitialized = true;
        emit ProjectInitialized(true);

    }

    /**
     * Lock the provided amount of token for "_relative_release_time" seconds starting from now
     * NOTE: This method is capped
     * NOTE: time definition in the locks is relative!
     */
    function insertLock(address account, uint256 _amount, uint256 _relative_release_time) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(totalSupply() + total_locked_amount + _amount <= cap(), "cap exceeded");

        uint256 sid = block.timestamp;

        Locks memory lock_ = Locks({
            identifier: sid,
            locked: _amount,
            release_time: block.timestamp + _relative_release_time,
            released: false
        });

        _locks[account].push(lock_);
        total_locked_amount += _amount;
        emit Locked(account, _amount);
    }

    function batchInsertLock(address account, uint256[] memory _amounts, uint256[] memory _relative_release_time) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_amounts.length == _relative_release_time.length);
        for(uint256 i = 0; i < _amounts.length; i++) {
            insertLock(account, _amounts[i], _relative_release_time[i]);
        }
    }

    function locksOf(address account) public view returns(Locks[] memory) {
        return _locks[account];
    }

    function getLockNumber(address account) public view returns(uint256) {
        return _locks[account].length;
    }

    function release(uint256 lock_id) public {
        require(_locks[msg.sender].length > 0, "notFound");
        require(_locks[msg.sender].length -1 >= lock_id, "noLeft");
        require(!_locks[msg.sender][lock_id].released, "Released");
        require(block.timestamp > _locks[msg.sender][lock_id].release_time, "notReady");

        total_locked_amount -= _locks[msg.sender][lock_id].locked;

        _locks[msg.sender][lock_id].released = true;

        _mint(msg.sender, _locks[msg.sender][lock_id].locked);

        emit Released(msg.sender, _locks[msg.sender][lock_id].locked);
    }

    // Override
    function _transfer(address sender, address recipient, uint256 amount) internal override {

        require(hasRole(BLACKLIST_ROLE, sender) == false && hasRole(BLACKLIST_ROLE, recipient) == false, "BL");

        if (isWhitelisted[sender] || isWhitelisted[recipient] || inSwap) {
            super._transfer(sender, recipient, amount);
            return;
        }

        require(tradingEnabled);

        if (_shouldSwapBack(isMarketMaker[recipient])) { _swapBack(); }

        uint256 amountAfterTaxes = _takeTax(sender, recipient, amount);

        super._transfer(sender, recipient, amountAfterTaxes);

    }

    // Public
    function getDynamicSellTax() public view returns (uint256) {
        uint256 endingTime = launchTime + 7 days;
        if (endingTime > block.timestamp) {
            uint256 remainingTime = endingTime - block.timestamp;
            return sellTax + sellTax * remainingTime / 7 days;
        } else {
            return sellTax;
        }
    }

    function _takeTax(address sender, address recipient, uint256 amount) private returns (uint256) {

        if (amount == 0) { return amount; }

        uint256 tax = _getTotalTax(sender, recipient);

        uint256 taxAmount = amount * tax / 100;

        if (taxAmount > 0) { super._transfer(sender, address(this), taxAmount); }

        return amount - taxAmount;

    }

    function _getTotalTax(address sender, address recipient) private view returns (uint256) {

        if (sniperTax) { return 99; }
        if (isCEX[recipient]) { return sellTax; }
        if (isCEX[sender]) { return buyTax; }

        if (isMarketMaker[sender]) {
            return buyTax;
        } else if (isMarketMaker[recipient]) {
            return dumpProtectionEnabled ? getDynamicSellTax() : sellTax;
        } else {
            return transferTax;
        }

    }

    function _shouldSwapBack(bool run) private view returns (bool) {
        return swapEnabled && run && balanceOf(address(this)) >= swapThreshold;
    }

    function _swapBack() private swapping {

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = PancakeSwapV2Router.WETH();

        uint256 liquidityTokens = swapThreshold * liquidityShare / totalShares / 2;
        uint256 amountToSwap = swapThreshold - liquidityTokens;
        uint256 balanceBefore = address(this).balance;

        PancakeSwapV2Router.swapExactTokensForETH(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 amountBNB = address(this).balance - balanceBefore;
        uint256 totalBNBShares = totalShares - liquidityShare / 2;

        uint256 amountBNBLiquidity = amountBNB * liquidityShare / totalBNBShares / 2;
        uint256 amountBNBMarketing = amountBNB * marketingShare / totalBNBShares;

        (bool marketingSuccess,) = payable(marketingWallet).call{value: amountBNBMarketing, gas: transferGas}("");
        if (marketingSuccess) { emit DepositMarketing(marketingWallet, amountBNBMarketing); }

        if (liquidityTokens > 0) {

            PancakeSwapV2Router.addLiquidityETH{value: amountBNBLiquidity}(
                address(this),
                liquidityTokens,
                0,
                0,
                address(this),
                block.timestamp
            );

            emit AutoLiquidity(amountBNBLiquidity, liquidityTokens);

        }

    }

    // Owner

    function migrateToNewTokens(address account, uint256 amount) external onlyRole(SWAPPING_ROLE) {
        _mint(account, amount);
        emit Swapped();
    }

    function disableDumpProtection() external onlyOwner {
        dumpProtectionEnabled = false;
        emit DisableDumpProtection();
    }

    function removeSniperTax() external onlyOwner {
        sniperTax = false;
        emit SniperTaxRemoved();
    }

    function enableTrading() external onlyOwner {
        require(!tradingEnabled);
        tradingEnabled = true;
        launchTime = block.timestamp;
        emit EnableTrading();

    }

    function triggerSwapBack() external onlyOwner {
        _swapBack();
        emit TriggerSwapBack();
    }

    function recoverBNB() external onlyOwner {
        uint256 amount = address(this).balance;
        (bool sent,) = payable(marketingWallet).call{value: amount, gas: transferGas}("");
        require(sent, "Tx failed");
        emit RecoverBNB(amount);
    }

    function recoverBEP20(IERC20Upgradeable token, address recipient) external onlyOwner {
        require(address(token) != address(this), "Can't withdraw");
        uint256 amount = token.balanceOf(address(this));
        token.transfer(recipient, amount);
        emit RecoverBEP20(address(token), amount);
    }

    function setIsWhitelisted(address account, bool value) external onlyOwner {
        isWhitelisted[account] = value;
        emit SetWhitelisted(account, value);
    }

    function setIsCEX(address account, bool value) external onlyOwner {
        isCEX[account] = value;
        emit SetCEX(account, value);
    }

    function setIsMarketMaker(address account, bool value) external onlyOwner {
        require(account != PancakeSwapV2Pair);
        isMarketMaker[account] = value;
        emit SetMarketMaker(account, value);
    }


    function setTaxes(uint256 newBuyTax, uint256 newSellTax, uint256 newTransferTax) external onlyOwner {
        require(newBuyTax <= 10 && newSellTax <= 20 && newTransferTax <= 10);
        buyTax = newBuyTax;
        sellTax = newSellTax;
        transferTax = newTransferTax;
        emit SetTaxes(buyTax, sellTax, transferTax);
    }

    function setShares(uint256 newLiquidityShare, uint256 newMarketingShare) external onlyOwner {
        liquidityShare = newLiquidityShare;
        marketingShare = newMarketingShare;
        totalShares = liquidityShare + marketingShare;
        emit SetShares(liquidityShare, marketingShare);
    }

    function setSwapBackSettings(bool enabled, uint256 amount) external onlyOwner {
        uint256 tokenAmount = amount * 10**decimals();
        swapEnabled = enabled;
        swapThreshold = tokenAmount;
        emit SetSwapBackSettings(enabled, amount);
    }

    function setTransferGas(uint256 newGas) external onlyOwner {
        require(newGas >= 25000 && newGas <= 500000);
        transferGas = newGas;
        emit SetTransferGas(newGas);
    }

    function setMarketingWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0));
        address oldWallet = marketingWallet;
        marketingWallet = newWallet;
        emit UpdateMarketingWallet(newWallet,oldWallet);
    }

}