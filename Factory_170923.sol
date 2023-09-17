//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./MAAL721.sol";
import "./MAAL1155.sol";

contract Pansea721NFTs is MAAL721A, Ownable {
    using Strings for uint256;

    string public baseURI;
    string public initialURI;

    uint256 public maxSupply;
    uint256 public mintPricePerNFT;
    uint256 public maxPerWallet;

    address public fundCollector;

    bool public isWhitelisted;
    bool public limitsActive;
    bool public revealed;

    mapping(address => bool) public whitelistedWallet;
    mapping(address => bool) public maxLimitReached;

    constructor(
        string memory name,
        string memory symbol,
        string memory _baseURI,
        uint256 _maxSupply,
        uint256 _mintPrice,
        uint256 _maxPerWallet,
        address _wallet,
        bool whitelistStatus,
        bool revealedOnMint
    ) MAAL721A(name, symbol) {
        maxSupply = _maxSupply;
        mintPricePerNFT = _mintPrice;
        maxPerWallet = _maxPerWallet;
        fundCollector = _wallet;
        isWhitelisted = whitelistStatus;
        revealed = revealedOnMint;

        if (revealedOnMint) {
            initialURI = _baseURI;
        } else {
            baseURI = _baseURI;
        }
        if(_maxPerWallet > 0) {
            limitsActive = true;
        }
    }

    function getBaseURI() public view returns (string memory) {
        return baseURI;
    }

    /**
     * @dev Get all NFT IDs owned by a specific address.
     * @param owner The address to query.
     * @return An array of token IDs owned by the address.
     */
    function getNFTsOwned(address owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256 balance = balanceOf(owner);
        uint256[] memory ownedNFTs = new uint256[](balance);

        if (balance > 0) {
            uint256 index = 0;
            for (uint256 tokenId = 0; tokenId < totalSupply(); tokenId++) {
                if (ownerOf(tokenId) == owner) {
                    ownedNFTs[index] = tokenId;
                    index++;
                }
            }
        }

        return ownedNFTs;
    }

    function mint(uint256 _amount) external payable {
        require(totalSupply() + _amount <= maxSupply, "Max supply exceeded");
        require(msg.value == mintPricePerNFT * _amount, "Error: pay mint price");

        if(limitsActive) {
            require(!maxLimitReached[msg.sender], "Max per wallet limit reached");
        }

        if (isWhitelisted) {
            require(
                whitelistedWallet[msg.sender],
                "Error: wallet not whitelisted"
            );
        }

        // Transfer Ether to the owner
        (bool transferSuccess, ) = payable(fundCollector).call{
            value: msg.value
        }("");
        require(transferSuccess, "Transfer failed");

        if(balanceOf(msg.sender) + _amount == maxPerWallet) {
            maxLimitReached[msg.sender] = true;
        }

        _mint(msg.sender, _amount);
    }

    function openPublicMinting() external onlyOwner {
        require(isWhitelisted, "Error: Already open to public minting");

        isWhitelisted = false;
    }

    function removeLimits() external onlyOwner{
        require(limitsActive, "Limit has already been removed");

        limitsActive = false;
    }

    // Function to bulk whitelist addresses for minting within a range
    function bulkWhitelistWallets(
        address[] memory accounts,
        bool state,
        uint256 start,
        uint256 end
    ) external onlyOwner {
        require(isWhitelisted, "Error: This is not a whitelisted mint");
        require(end <= accounts.length, "End value is out of bounds");

        for (uint256 i = start; i < end; i++) {
            whitelistedWallet[accounts[i]] = state;
        }
    }

    /// @notice - Get token URI
    /// @param tokenId - Token ID of NFT
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        if (!revealed)
            return
                bytes(initialURI).length != 0
                    ? string(
                        abi.encodePacked(
                            initialURI,
                            tokenId.toString(),
                            ".json"
                        )
                    )
                    : "No initial URI set";
        else
            return
                bytes(baseURI).length != 0
                    ? string(
                        abi.encodePacked(baseURI, tokenId.toString(), ".json")
                    )
                    : initialURI;
    }

    function revealNFTs(string memory _newBaseURI) external onlyOwner {
        require(!revealed, "Error: NFTs are already revealed");
        baseURI = _newBaseURI;
    }
}

contract Pansea1155NFTs is MAAL1155, Ownable {
    string public name;
    string public symbol;
    string private _uri;
    uint256 public totalSupply;
    mapping(uint256 => uint256) public tokenSupply;

    mapping(address => bool) public blacklisted;

    constructor(
        string memory _contractName,
        string memory _contractSymbol,
        uint256 _id,
        uint256 _totalSupply,
        string memory _newURI
    ) MAAL1155(_newURI) {
        name = _contractName;
        symbol = _contractSymbol;
        totalSupply = _totalSupply;

        transferOwnership(tx.origin);
        mint(tx.origin, _id, totalSupply);
    }

    function mint(
        address to,
        uint256 _id,
        uint256 _amount
    ) private returns (uint256) {
        _mint(to, _id, _amount, "");
        tokenSupply[_id] = _amount;

        return (_id);
    }

    function mintBatch(uint256[] memory _ids, uint256[] memory _amounts)
        external
        onlyOwner
    {
        _mintBatch(msg.sender, _ids, _amounts, "");
        for (uint256 i = 0; i < _ids.length; i++) {
            tokenSupply[_ids[i]] = _amounts[i];
        }
    }

    function getURI() public view returns (string memory) {
        return (_uri);
    }

    function setURI(string memory _newURI) public onlyOwner {
        _setURI(_newURI);
    }
}

contract PanSeaFactory {
    using Counters for Counters.Counter;
    Counters.Counter private _counter;

    address[] public contractsList;

    event CollectionCreated(address);

    mapping(address => address[]) private UserNFTContracts;

    // mapping(uint256 => address) public indexToOwner; //index to NFT owner address

    constructor() {}

    function createNFT721(
        string memory name,
        string memory symbol,
        string memory baseURI,
        uint256 _maxSupply,
        uint256 _mintPrice,
        uint256 _maxPerWallet,
        address _wallet,
        bool _whitelistStatus,
        bool _revealedOnMint
    ) external returns (address newNFTCollectionAddress) {
        Pansea721NFTs newNFTCollection = new Pansea721NFTs(
            name,
            symbol,
            baseURI,
            _maxSupply,
            _mintPrice,
            _maxPerWallet,
            _wallet,
            _whitelistStatus,
            _revealedOnMint
        );
        newNFTCollection.transferOwnership(msg.sender);
        contractsList.push(address(newNFTCollection));
        _counter.increment();

        // Mapping NFT IDs to the investor address
        UserNFTContracts[msg.sender].push(address(newNFTCollection));

        emit CollectionCreated(address(newNFTCollection));
        return address(newNFTCollection);
    }

    function createNFT1155(
        string memory _name,
        string memory _symbol,
        uint256 _id,
        uint256 _totalSupply,
        string memory _newURI
    ) external returns (address newNFTCollectionAddress) {
        Pansea1155NFTs newNFTCollection = new Pansea1155NFTs(
            _name,
            _symbol,
            _id,
            _totalSupply,
            _newURI
        );
        contractsList.push(address(newNFTCollection));
        _counter.increment();

        // Mapping NFT IDs to the investor address
        UserNFTContracts[msg.sender].push(address(newNFTCollection));

        emit CollectionCreated(address(newNFTCollection));
        return address(newNFTCollection);
    }

    function deployedCounter() public view returns (uint256 __counter) {
        return _counter.current();
    }

    function deployedContracts() public view returns (address[] memory) {
        return contractsList;
    }

    // Return all NFT addresses held by an address
    function getUserNFTContracts(address minter)
        external
        view
        returns (address[] memory contracts)
    {
        address[] memory arr = UserNFTContracts[minter];
        return arr;
    }
}
