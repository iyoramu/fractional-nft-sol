// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract FractionalNFT is ERC721, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    // Fractional ERC20 token representing shares of the NFT
    ERC20 public fractionalToken;
    
    // NFT metadata
    string private _nftURI;
    uint256 public constant TOTAL_SHARES = 1_000_000; // 1 million shares
    uint256 public constant MIN_BUYOUT = TOTAL_SHARES.mul(75).div(100); // 75% required for buyout
    
    // Auction parameters
    uint256 public auctionEndTime;
    uint256 public highestBid;
    address public highestBidder;
    bool public buyoutTriggered;
    
    // Events
    event Fractionalized(uint256 totalShares);
    event BuyoutInitiated(address initiator, uint256 auctionEndTime);
    event BidPlaced(address bidder, uint256 amount);
    event BuyoutCompleted(address winner, uint256 amount);
    event Redeemed(address redeemer, uint256 shares);
    
    constructor(string memory name, string memory symbol, string memory nftURI) 
        ERC721(name, symbol) 
    {
        _nftURI = nftURI;
    }
    
    // Fractionalize the NFT by minting ERC20 shares
    function fractionalize() external onlyOwner {
        require(address(fractionalToken) == address(0), "Already fractionalized");
        
        // Create ERC20 token representing shares
        fractionalToken = new ERC20("Fractionalized NFT Shares", "FNFT");
        
        // Mint all shares to NFT owner
        fractionalToken.transfer(msg.sender, TOTAL_SHARES);
        
        emit Fractionalized(TOTAL_SHARES);
    }
    
    // Initiate buyout process by starting an auction
    function initiateBuyout() external nonReentrant {
        require(address(fractionalToken) != address(0), "Not fractionalized");
        require(!buyoutTriggered, "Buyout already initiated");
        
        // Check if caller has enough shares (75%)
        uint256 callerShares = fractionalToken.balanceOf(msg.sender);
        require(callerShares >= MIN_BUYOUT, "Insufficient shares for buyout");
        
        // Start 7-day auction
        auctionEndTime = block.timestamp + 7 days;
        buyoutTriggered = true;
        
        emit BuyoutInitiated(msg.sender, auctionEndTime);
    }
    
    // Place a bid in the buyout auction
    function placeBid() external payable nonReentrant {
        require(buyoutTriggered, "Buyout not initiated");
        require(block.timestamp < auctionEndTime, "Auction ended");
        require(msg.value > highestBid, "Bid too low");
        
        // Return previous highest bid
        if (highestBidder != address(0)) {
            payable(highestBidder).transfer(highestBid);
        }
        
        highestBid = msg.value;
        highestBidder = msg.sender;
        
        emit BidPlaced(msg.sender, msg.value);
    }
    
    // Complete the buyout after auction ends
    function completeBuyout() external nonReentrant {
        require(buyoutTriggered, "Buyout not initiated");
        require(block.timestamp >= auctionEndTime, "Auction not ended");
        
        // Distribute proceeds to fractional token holders proportionally
        if (highestBidder != address(0)) {
            // Calculate total supply for pro-rata distribution
            uint256 totalSupply = fractionalToken.totalSupply();
            
            // Burn all fractional tokens
            for (uint256 i = 0; i < totalSupply; i++) {
                address holder = fractionalToken.tokenOfOwnerByIndex(i, 0);
                uint256 balance = fractionalToken.balanceOf(holder);
                if (balance > 0) {
                    fractionalToken.burn(holder, balance);
                    uint256 shareValue = highestBid.mul(balance).div(totalSupply);
                    payable(holder).transfer(shareValue);
                }
            }
            
            // Transfer NFT to winning bidder
            _transfer(owner(), highestBidder, 0);
            
            emit BuyoutCompleted(highestBidder, highestBid);
        }
    }
    
    // Redeem shares for underlying NFT (if buyout not initiated)
    function redeem(uint256 shares) external nonReentrant {
        require(address(fractionalToken) != address(0), "Not fractionalized");
        require(!buyoutTriggered, "Buyout initiated - cannot redeem");
        
        // Burn shares
        fractionalToken.burn(msg.sender, shares);
        
        // If redeemer now owns 100%, transfer NFT
        if (fractionalToken.balanceOf(msg.sender) == TOTAL_SHARES) {
            _transfer(owner(), msg.sender, 0);
        }
        
        emit Redeemed(msg.sender, shares);
    }
    
    // Override tokenURI to return stored metadata
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");
        return _nftURI;
    }
    
    // Fallback to reject accidental ETH transfers
    receive() external payable {
        revert("Direct ETH transfers not allowed");
    }
}

// Custom ERC20 implementation with burn functionality
contract ERC20 is Context, IERC20, IERC20Metadata {
    using SafeMath for uint256;
    
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }
    
    function name() public view virtual override returns (string memory) {
        return _name;
    }
    
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }
    
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }
    
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }
    
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }
    
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }
    
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }
    
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }
    
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        
        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }
    
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");
        
        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }
    
    function burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");
        
        _balances[account] = _balances[account].sub(amount, "ERC20: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }
    
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}
