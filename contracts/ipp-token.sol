// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import './libs/SafeMath.sol';
import './libs/Address.sol';
import './libs/CfoTakeableV2.sol';
import './libs/IERC20Metadata.sol';
import './libs/ChainId.sol';

interface ISwapFactory {
    function getPair(address token0,address token1) external view returns(address);
}

contract IPP is CfoTakeableV2,IERC20Metadata {
    using Address for address;
    using SafeMath for uint256;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    string private constant _name = "IPP";
    string private constant _symbol = "IPP";
    uint256 private constant _totalSupply = 16000000 * 1e18;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the permit struct used by the contract
    bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    bytes32 public immutable DOMAIN_SEPARATOR;

    /// @notice A record of states for signing / validating signatures
    mapping (address => uint) public nonces;
    
    mapping(address => bool) public isOtherSwapPair;

    uint private constant RATE_PERCISION = 10000;
    uint public buyFeeRate;
    uint public sellFeeRate;
    address public feeTo = address(0x031c5aC63551fA69F8841435990b150f69f9a4A6);

    ISwapFactory public immutable ippSwapFactory;

    // testnet
    address public constant usdt = address(0x8C43FbebAA2dED5a50C10766b0F03a151f2bBf17);
    address public constant wbnb = address(0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd);
    ISwapFactory public constant bitbyteSwapFactory = ISwapFactory(address(0xA47D4e248a93933a33Ad3653cD8bf8F9214A5Fe7));
    ISwapFactory public constant pancakeSwapFactory = ISwapFactory(address(0x6725F303b657a9451d8BA641348b6761A6CC7a17));
    address public constant liquidityProxy = address(0xf77F7506500Adf57771251510Bb4e9268857b059);

    // mainnet
    // address public constant usdt = address(0x55d398326f99059fF775485246999027B3197955);
    // address public constant wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    // ISwapFactory public constant bitbyteSwapFactory = ISwapFactory(address(0x49CDaFf8F36d3021Ff6bC4F480682752C80e0F28));
    // ISwapFactory public constant pancakeSwapFactory = ISwapFactory(address(0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73));
    // address public constant liquidityProxy = address(0xf420f9168224609b5C393bAa6cb59f144643bb09);

    constructor(
        address _initHolder,
        address _ippSwapFactory
    ){

        DOMAIN_SEPARATOR = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(_name)), ChainId.get(), address(this)));

        require(_ippSwapFactory != address(0),"ipp swap factory can not be address 0");
        ippSwapFactory = ISwapFactory(_ippSwapFactory);

        address holder = _initHolder == address(0) ? msg.sender : _initHolder;
        _balances[holder] = _totalSupply;
        emit Transfer(address(0), holder, _totalSupply);
    }

    function name() public pure override returns (string memory) {
        return _name;
    }

    function symbol() public pure override returns (string memory) {
        return _symbol;
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function totalSupply() public pure override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function permit(address owner, address spender, uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(block.timestamp <= deadline, "ERC20permit: expired");
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, amount, nonces[owner]++, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "ERC20permit: invalid signature");
        require(signatory == owner, "ERC20permit: unauthorized");

        _approve(owner, spender, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        require(_balances[sender] >= amount, "ERC20: transfer amount exceeds balance");

        uint recipientAmount = amount;
        bool isBuy = isSwapPair(sender);
        bool isSell = isSwapPair(recipient);
        if(recipient != address(0) && sender != liquidityProxy && recipient != liquidityProxy && (isBuy || isSell)){
            uint feeRate = isBuy ? buyFeeRate : sellFeeRate;
            uint feeAmount = amount.mul(feeRate) / RATE_PERCISION;
            recipientAmount -= feeAmount;
            _takeFee(sender, feeTo, feeAmount);
        }
        
        _balances[sender] = _balances[sender].sub(amount);
        _balances[recipient] = _balances[recipient].add(recipientAmount);
        emit Transfer(sender, recipient, recipientAmount);

        _afterTokenTransfer(sender, recipient, amount);
    }

    function _takeFee(address _from,address _to,uint _fee) internal {
        if(_fee > 0){
            _balances[_to] = _balances[_to].add(_fee);
            emit Transfer(_from, _to, _fee);
        }
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal {}

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal {}

    function isSwapPair(address pair) public view returns(bool){
        if(pair == address(0)){
            return false;
        }

        return ippSwapFactory.getPair(address(this), usdt) == pair || ippSwapFactory.getPair(address(this), wbnb) == pair || 
        bitbyteSwapFactory.getPair(address(this), usdt) == pair || bitbyteSwapFactory.getPair(address(this), wbnb) == pair || 
        pancakeSwapFactory.getPair(address(this), usdt) == pair || pancakeSwapFactory.getPair(address(this), wbnb) == pair || 
        isOtherSwapPair[pair];
    }

    function addOtherSwapPair(address _swapPair) external onlyOwner {
        require(_swapPair != address(0),"_swapPair can not be address 0");
        isOtherSwapPair[_swapPair] = true;
    }

    function removeOtherSwapPair(address _swapPair) external onlyOwner {
        require(_swapPair != address(0),"_swapPair can not be address 0");
        isOtherSwapPair[_swapPair] = false;
    }

    function setBuyFeeRate(uint _rate) external onlyOwner {
        require(_rate <= RATE_PERCISION,"rate too large");
        buyFeeRate = _rate;
    }

    function setSellFeeRate(uint _rate) external onlyOwner {
        require(_rate <= RATE_PERCISION,"rate too large");
        sellFeeRate = _rate;
    }

    function setFeeTo(address _feeTo) external onlyOwner {
        feeTo = _feeTo;
    }
}