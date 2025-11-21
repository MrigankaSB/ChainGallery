// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ChainGallery
 * @dev Decentralized Digital Art Gallery with ERC-721 NFT implementation
 * @notice This contract enables artists to mint, exhibit, and sell digital artwork on blockchain
 */

contract Project {
    // Gallery metadata
    string public name = "ChainGallery";
    string public symbol = "CGART";
    
    // Counters
    uint256 private _tokenIdCounter;
    uint256 private _exhibitionIdCounter;
    
    // Contract owner
    address public owner;
    
    // Gallery commission (in basis points, 250 = 2.5%)
    uint256 public galleryCommission = 250;
    uint256 public constant COMMISSION_DENOMINATOR = 10000;
    
    // Artist royalty percentage (750 = 7.5%)
    uint256 public artistRoyalty = 750;
    
    // Reentrancy protection
    bool private locked;
    
    // ERC-721 mappings
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    
    // Artwork metadata
    mapping(uint256 => string) private _tokenURIs;
    mapping(uint256 => address) private _artists;
    mapping(uint256 => uint256) private _artworkPrices;
    mapping(uint256 => bool) private _forSale;
    
    // Exhibition system
    struct Exhibition {
        uint256 exhibitionId;
        string title;
        address curator;
        uint256[] artworks;
        uint256 startTime;
        uint256 endTime;
        bool active;
    }
    
    mapping(uint256 => Exhibition) public exhibitions;
    mapping(address => uint256[]) private _artistArtworks;
    
    // Artist profiles
    mapping(address => bool) public verifiedArtists;
    mapping(address => string) public artistProfiles;
    
    // Events
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event ArtworkMinted(address indexed artist, uint256 indexed tokenId, string tokenURI);
    event ArtworkListed(uint256 indexed tokenId, uint256 price);
    event ArtworkSold(uint256 indexed tokenId, address indexed buyer, address indexed seller, uint256 price);
    event ExhibitionCreated(uint256 indexed exhibitionId, string title, address indexed curator);
    event ArtistVerified(address indexed artist);
    event RoyaltyPaid(uint256 indexed tokenId, address indexed artist, uint256 amount);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Not gallery owner");
        _;
    }
    
    modifier nonReentrant() {
        require(!locked, "Reentrancy detected");
        locked = true;
        _;
        locked = false;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    // ERC-721 Standard Functions
    
    function balanceOf(address tokenOwner) public view returns (uint256) {
        require(tokenOwner != address(0), "Zero address query");
        return _balances[tokenOwner];
    }
    
    function ownerOf(uint256 tokenId) public view returns (address) {
        address tokenOwner = _owners[tokenId];
        require(tokenOwner != address(0), "Artwork does not exist");
        return tokenOwner;
    }
    
    function tokenURI(uint256 tokenId) public view returns (string memory) {
        require(_owners[tokenId] != address(0), "Artwork does not exist");
        return _tokenURIs[tokenId];
    }
    
    function approve(address to, uint256 tokenId) public {
        address tokenOwner = ownerOf(tokenId);
        require(msg.sender == tokenOwner || isApprovedForAll(tokenOwner, msg.sender), "Not authorized");
        _tokenApprovals[tokenId] = to;
        emit Approval(tokenOwner, to, tokenId);
    }
    
    function getApproved(uint256 tokenId) public view returns (address) {
        require(_owners[tokenId] != address(0), "Artwork does not exist");
        return _tokenApprovals[tokenId];
    }
    
    function setApprovalForAll(address operator, bool approved) public {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }
    
    function isApprovedForAll(address tokenOwner, address operator) public view returns (bool) {
        return _operatorApprovals[tokenOwner][operator];
    }
    
    function transferFrom(address from, address to, uint256 tokenId) public {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Transfer not authorized");
        require(ownerOf(tokenId) == from, "From address mismatch");
        require(to != address(0), "Transfer to zero address");
        require(!_forSale[tokenId], "Cannot transfer artwork listed for sale");
        
        _tokenApprovals[tokenId] = address(0);
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;
        
        emit Transfer(from, to, tokenId);
    }
    
    // Artwork Minting and Management
    
    function mintArtwork(string memory uri) public returns (uint256) {
        _tokenIdCounter++;
        uint256 newTokenId = _tokenIdCounter;
        
        _balances[msg.sender] += 1;
        _owners[newTokenId] = msg.sender;
        _tokenURIs[newTokenId] = uri;
        _artists[newTokenId] = msg.sender;
        _artistArtworks[msg.sender].push(newTokenId);
        
        emit Transfer(address(0), msg.sender, newTokenId);
        emit ArtworkMinted(msg.sender, newTokenId, uri);
        
        return newTokenId;
    }
    
    function listArtworkForSale(uint256 tokenId, uint256 price) public {
        require(ownerOf(tokenId) == msg.sender, "Not artwork owner");
        require(price > 0, "Price must be greater than zero");
        
        _artworkPrices[tokenId] = price;
        _forSale[tokenId] = true;
        
        emit ArtworkListed(tokenId, price);
    }
    
    function removeFromSale(uint256 tokenId) public {
        require(ownerOf(tokenId) == msg.sender, "Not artwork owner");
        _forSale[tokenId] = false;
    }
    
    function purchaseArtwork(uint256 tokenId) public payable nonReentrant {
        require(_forSale[tokenId], "Artwork not for sale");
        require(msg.value >= _artworkPrices[tokenId], "Insufficient payment");
        
        address seller = ownerOf(tokenId);
        address artist = _artists[tokenId];
        uint256 price = _artworkPrices[tokenId];
        
        // Calculate distributions
        uint256 commission = (price * galleryCommission) / COMMISSION_DENOMINATOR;
        uint256 royalty = (price * artistRoyalty) / COMMISSION_DENOMINATOR;
        uint256 sellerAmount = price - commission - royalty;
        
        // Update state before transfers
        _forSale[tokenId] = false;
        _tokenApprovals[tokenId] = address(0);
        _balances[seller] -= 1;
        _balances[msg.sender] += 1;
        _owners[tokenId] = msg.sender;
        
        // Transfer funds
        payable(seller).transfer(sellerAmount);
        payable(artist).transfer(royalty);
        payable(owner).transfer(commission);
        
        // Refund excess
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
        
        emit Transfer(seller, msg.sender, tokenId);
        emit ArtworkSold(tokenId, msg.sender, seller, price);
        emit RoyaltyPaid(tokenId, artist, royalty);
    }
    
    // Exhibition Management
    
    function createExhibition(
        string memory title,
        uint256[] memory artworkIds,
        uint256 duration
    ) public returns (uint256) {
        _exhibitionIdCounter++;
        uint256 exhibitionId = _exhibitionIdCounter;
        
        exhibitions[exhibitionId] = Exhibition({
            exhibitionId: exhibitionId,
            title: title,
            curator: msg.sender,
            artworks: artworkIds,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            active: true
        });
        
        emit ExhibitionCreated(exhibitionId, title, msg.sender);
        return exhibitionId;
    }
    
    function closeExhibition(uint256 exhibitionId) public {
        Exhibition storage exhibition = exhibitions[exhibitionId];
        require(exhibition.curator == msg.sender || msg.sender == owner, "Not authorized");
        exhibition.active = false;
    }
    
    // Artist Management
    
    function verifyArtist(address artist) public onlyOwner {
        verifiedArtists[artist] = true;
        emit ArtistVerified(artist);
    }
    
    function setArtistProfile(string memory profileURI) public {
        artistProfiles[msg.sender] = profileURI;
    }
    
    function getArtistArtworks(address artist) public view returns (uint256[] memory) {
        return _artistArtworks[artist];
    }
    
    // Administrative Functions
    
    function setGalleryCommission(uint256 newCommission) public onlyOwner {
        require(newCommission <= 1000, "Commission too high");
        galleryCommission = newCommission;
    }
    
    function setArtistRoyalty(uint256 newRoyalty) public onlyOwner {
        require(newRoyalty <= 2000, "Royalty too high");
        artistRoyalty = newRoyalty;
    }
    
    function withdrawCommissions() public onlyOwner nonReentrant {
        payable(owner).transfer(address(this).balance);
    }
    
    // Helper Functions
    
    function _isApprovedOrOwner(address spender, uint256 tokenId) private view returns (bool) {
        address tokenOwner = ownerOf(tokenId);
        return (spender == tokenOwner || 
                getApproved(tokenId) == spender || 
                isApprovedForAll(tokenOwner, spender));
    }
    
    function getArtist(uint256 tokenId) public view returns (address) {
        require(_owners[tokenId] != address(0), "Artwork does not exist");
        return _artists[tokenId];
    }
    
    function getArtworkPrice(uint256 tokenId) public view returns (uint256) {
        return _artworkPrices[tokenId];
    }
    
    function isForSale(uint256 tokenId) public view returns (bool) {
        return _forSale[tokenId];
    }
    
    function totalArtworks() public view returns (uint256) {
        return _tokenIdCounter;
    }
}

