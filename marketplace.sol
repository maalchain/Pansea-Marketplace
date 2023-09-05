// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract MedinaNFTMarketplace is Pausable, ReentrancyGuard {
    address public owner;
    uint256 public platformFee; // 250 ~ 2.5%
    uint256 public maxRoyaltyFee = 750; // 750 ~ 7.5%

    // IERC20 public USDT;

    struct Collection {
        uint256 collectionId;
        address creator;
        uint256 royaltyFee; // 750 ~ 7.5%
        address walletForRoyalty;
        mapping(uint256 => uint256[]) NFTListingsByCollection;
    }

    struct NFTListing {
        uint256 collectionId;
        uint256 listingId;
        address NFTContractAddress;
        address seller;
        uint256 TokenId;
        uint256 QuantityOnSale;
        IERC20 tokenAdd;
        uint256 PricePerNFT;
        uint256 listingExpireTime;
        uint256 listingStatus; // 0 = inactive, 1 = active, 2 = sold
        uint256[] offers;
    }

    struct Offer {
        uint256 offerId;
        address NFTContractAddress;
        uint256 listingId;
        uint256 TokenId;
        uint256 quantityOfferedForPurchase;
        IERC20 tokenAdd;
        uint256 pricePerNFT;
        uint256 offerExpireTime;
        address offerCreator;
        bool isActive;
        uint256 lockedValue; // value locked into the contract
    }

    mapping(uint256 => Collection) public collections;
    mapping(uint256 => NFTListing) public NFTListings;
    mapping(uint256 => Offer) public offers;
    mapping(uint256 => mapping(uint256 => uint256)) public _offersByListing;
    mapping(uint256 => uint256[]) public NFTListingsByCollection;
    uint256 public collectionIdCounter;
    uint256 public listingIdCounter;
    uint256 public offerIdCounter;

    event CollectionCreated(
        uint256 collectionId,
        uint256 royaltyFee,
        address walletForRoyalty
    );

    event CollectionEdited(
        uint256 collectionId,
        uint256 royaltyFee,
        address walletForRoyalty
    );
    event NFTListed(
        uint256 collectionId,
        uint256 listingId,
        address NFTContractAddress,
        uint256 TokenId,
        uint256 QuantityOnSale,
        IERC20 tokenAdd,
        uint256 PricePerNFT,
        uint256 listingExpireTime
    );
    event ListingUpdated(
        uint256 listingId,
        address NFTContractAddress,
        uint256 TokenId,
        uint256 listingExpireTime
    );
    event ListingStatusUpdated(uint256 lisitngId, uint256 statusCode);
    event OfferCreated(
        uint256 offerId,
        uint256 collectionId,
        uint256 TokenId,
        uint256 quantityOfferedForPurchase,
        IERC20 tokenAdd,
        uint256 pricePerNFT,
        uint256 offerExpireTime
    );
    event OfferModified(
        uint256 offerId,
        uint256 pricePerNFT,
        uint256 offerExpireTime
    );
    event OfferCancelled(uint256 offerId);
    event OfferAccepted(uint256 offerId, address buyer);
    event NFTBought(uint256 listingId, uint256 quantity, address buyer);
    event TokenRecovery(address indexed tokenAddress, uint256 indexed amount);
    event NFTRecovery(
        address indexed collectionAddress,
        uint256 indexed tokenId
    );
    event Pause(string reason);
    event Unpause(string reason);

    constructor(uint256 _platformFee) {
        owner = msg.sender;
        platformFee = _platformFee;
        // USDT = _USDT;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    /* COllections */

    function getCollectionsByOwner(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256 count = 0;

        // Loop through all collections to count the number owned by the specified user
        for (uint256 i = 1; i <= collectionIdCounter; i++) {
            if (collections[i].creator == _owner) {
                count++;
            }
        }

        // Create an array of the correct size to store the collection IDs
        uint256[] memory collectionIds = new uint256[](count);

        // Loop through all collections to populate the array with the IDs owned by the specified user
        uint256 index = 0;
        for (uint256 i = 1; i <= collectionIdCounter; i++) {
            if (collections[i].creator == _owner) {
                collectionIds[index] = i;
                index++;
            }
        }

        return collectionIds;
    }

    function addCollection(uint256 _royaltyFee, address _walletForRoyalty)
        external
    {
        require(_royaltyFee <= maxRoyaltyFee, "Royalty fee too high");
        require(
            _walletForRoyalty != address(0),
            "Invalid royalty wallet address"
        );

        collectionIdCounter++;
        Collection storage newCollection = collections[collectionIdCounter];
        newCollection.collectionId = collectionIdCounter;
        newCollection.creator = msg.sender;
        newCollection.royaltyFee = _royaltyFee;
        newCollection.walletForRoyalty = _walletForRoyalty;

        emit CollectionCreated(
            collectionIdCounter,
            _royaltyFee,
            _walletForRoyalty
        );
    }

    function editCollection(
        uint256 _collectionId,
        uint256 _royaltyFee,
        address _walletForRoyalty
    ) external whenNotPaused nonReentrant {
        Collection storage collection = collections[_collectionId];

        require(
            collection.creator == msg.sender,
            "Only the collection creator can edit the collection"
        );
        require(
            _royaltyFee <= maxRoyaltyFee,
            "Royalty fee exceeds maximum allowed"
        );
        require(
            _walletForRoyalty != address(0),
            "Invalid royalty wallet address"
        );

        collection.royaltyFee = _royaltyFee;
        collection.walletForRoyalty = _walletForRoyalty;

        emit CollectionEdited(_collectionId, _royaltyFee, _walletForRoyalty);
    }

    /* NFT listing functions */

    function getNFTListingsBySeller(address _seller)
        public
        view
        returns (uint256[] memory)
    {
        uint256 count = 0;

        // Loop through all NFT listings to count the number listed by the specified user
        for (uint256 i = 1; i <= listingIdCounter; i++) {
            if (NFTListings[i].seller == _seller) {
                count++;
            }
        }

        // Create an array of the correct size to store the NFT listing IDs
        uint256[] memory listingIds = new uint256[](count);

        // Loop through all NFT listings to populate the array with the IDs listed by the specified user
        uint256 index = 0;
        for (uint256 i = 1; i <= listingIdCounter; i++) {
            if (NFTListings[i].seller == _seller) {
                listingIds[index] = i;
                index++;
            }
        }

        return listingIds;
    }

    function getListingsByNFT(address _NFTContractAddress, uint256 _TokenId)
        public
        view
        returns (uint256[] memory)
    {
        uint256 count = 0;

        // Loop through all NFT listings to count the number with the specified NFT Contract Address and Token ID
        for (uint256 i = 1; i <= listingIdCounter; i++) {
            if (
                NFTListings[i].NFTContractAddress == _NFTContractAddress &&
                NFTListings[i].TokenId == _TokenId
            ) {
                count++;
            }
        }

        // Create an array of the correct size to store the listing IDs
        uint256[] memory listingIds = new uint256[](count);

        // Loop through all NFT listings to populate the array with the IDs with the specified NFT Contract Address and Token ID
        uint256 index = 0;
        for (uint256 i = 1; i <= listingIdCounter; i++) {
            if (
                NFTListings[i].NFTContractAddress == _NFTContractAddress &&
                NFTListings[i].TokenId == _TokenId
            ) {
                listingIds[index] = i;
                index++;
            }
        }

        return listingIds;
    }

    function listNFT(
        uint256 collectionId,
        address NFTContractAddress,
        uint256 TokenId,
        uint256 QuantityOnSale,
        IERC20 tokenAdd,
        uint256 PricePerNFT,
        uint256 listingExpireTime
    ) external whenNotPaused nonReentrant {
        Collection storage collection = collections[collectionId];
        require(
            collection.creator == msg.sender,
            "Only the collection creator can list NFTs"
        );
        require(
            NFTContractAddress != address(0),
            "Invalid NFT contract address"
        );
        require(
            QuantityOnSale > 0,
            "Quantity on sale should be greater than zero"
        );
        require(PricePerNFT > 0, "Price per NFT should be greater than zero");
        require(
            listingExpireTime > block.timestamp,
            "Listing expire time should be in the future"
        );

        // Determine if NFT is ERC721 or ERC1155
        bool isERC721 = _supportsERC721Interface(NFTContractAddress);
        bool isERC1155 = _supportsERC1155Interface(NFTContractAddress);

        // Additional validations based on NFT type
        if (isERC721) {
            // ERC721 specific validations
            require(
                IERC721(NFTContractAddress).ownerOf(TokenId) == msg.sender,
                "Seller does not own the NFT"
            );
            require(
                IERC721(NFTContractAddress).getApproved(TokenId) ==
                    address(this),
                "Marketplace contract is not approved to transfer NFT"
            );
        } else if (isERC1155) {
            // ERC1155 specific validations
            require(
                IERC1155(NFTContractAddress).balanceOf(msg.sender, TokenId) >=
                    QuantityOnSale,
                "Seller does not own enough NFTs"
            );
            require(
                IERC1155(NFTContractAddress).isApprovedForAll(
                    msg.sender,
                    address(this)
                ),
                "Marketplace contract is not approved to transfer NFTs"
            );
        }

        listingIdCounter++;
        NFTListing storage newListing = NFTListings[listingIdCounter];
        newListing.collectionId = collectionId;
        newListing.listingId = listingIdCounter;
        newListing.NFTContractAddress = NFTContractAddress;
        newListing.seller = msg.sender;
        newListing.TokenId = TokenId;
        newListing.QuantityOnSale = QuantityOnSale;
        newListing.tokenAdd = tokenAdd;
        newListing.PricePerNFT = PricePerNFT;
        newListing.listingExpireTime = listingExpireTime;
        newListing.listingStatus = 1; // active

        collection.NFTListingsByCollection[TokenId].push(listingIdCounter);
        NFTListingsByCollection[collectionId].push(listingIdCounter);
        _offersByListing[listingIdCounter][0] = 0;

        emit NFTListed(
            collectionId,
            listingIdCounter,
            NFTContractAddress,
            TokenId,
            QuantityOnSale,
            tokenAdd,
            PricePerNFT,
            listingExpireTime
        );
    }

    function extendListingTime(uint256 _listingId, uint256 _listingExpireTime)
        external
        whenNotPaused
        nonReentrant
    {
        NFTListing storage listing = NFTListings[_listingId];

        require(
            msg.sender == listing.seller,
            "Only the seller can update the listing"
        );
        require(
            listing.listingStatus == 1,
            "Listing is not active and cannot be updated"
        );
        require(
            _listingExpireTime > block.timestamp &&
                _listingExpireTime > listing.listingExpireTime,
            "Invalid expire time"
        );

        listing.listingExpireTime = _listingExpireTime;

        emit ListingUpdated(
            _listingId,
            listing.NFTContractAddress,
            listing.TokenId,
            _listingExpireTime
        );
    }

    // Check if the contract supports ERC721 interface
    function _supportsERC721Interface(address contractAddress)
        internal
        view
        returns (bool)
    {
        return _functionExists(contractAddress, "ownerOf(uint256)");
    }

    // Check if the contract supports ERC1155 interface
    function _supportsERC1155Interface(address contractAddress)
        internal
        view
        returns (bool)
    {
        return
            _functionExists(
                contractAddress,
                "balanceOfBatch(address[],uint256[])"
            );
    }

    // Helper function to check if a function exists on the contract
    function _functionExists(
        address contractAddress,
        string memory functionName
    ) internal view returns (bool) {
        (bool success, bytes memory result) = contractAddress.staticcall(
            abi.encodeWithSignature(functionName)
        );
        return success && result.length > 0;
    }

    function updateListingStatus(uint256 _listingId, uint256 _listingStatus)
        external
    {
        NFTListing storage listing = NFTListings[_listingId];
        // Check that the caller is the owner of the listing
        require(
            msg.sender == listing.seller,
            "Only the owner of the listing can update the status"
        );
        // check that listing is not being set to sold status
        require(_listingStatus < 2, "Wrong status code");

        // Check that the listing is not already in the requested status
        require(
            listing.listingStatus != _listingStatus,
            "The listing is already in the requested status"
        );

        // Update the listing status
        listing.listingStatus = _listingStatus;

        // Emit an event to indicate that the status has been updated
        emit ListingStatusUpdated(_listingId, _listingStatus);
    }

    /* Offers */

    function getOffersByListing(uint256 _listingId)
        external
        view
        returns (uint256[] memory)
    {
        require(
            NFTListings[_listingId].listingStatus == 1,
            "Listing is not active"
        );

        uint256[] memory offersList = NFTListings[_listingId].offers;
        uint256[] memory activeOffers = new uint256[](offersList.length);
        uint256 index = 0;

        for (uint256 i = 0; i < offersList.length; i++) {
            if (offers[offersList[i]].isActive) {
                activeOffers[index] = offersList[i];
                index++;
            }
        }

        uint256[] memory finalOffers = new uint256[](index);

        for (uint256 i = 0; i < index; i++) {
            finalOffers[i] = activeOffers[i];
        }

        return finalOffers;
    }

    function getOffersByOfferCreator(address _offerCreator)
        public
        view
        returns (Offer[] memory)
    {
        uint256 count = 0;

        // Loop through all offers to count the number made by the specified user
        for (uint256 i = 1; i <= offerIdCounter; i++) {
            if (offers[i].offerCreator == _offerCreator) {
                count++;
            }
        }

        // Create an array of the correct size to store the offers made by the specified user
        Offer[] memory offersByUser = new Offer[](count);

        // Loop through all offers to populate the array with the offers made by the specified user
        uint256 index = 0;
        for (uint256 i = 1; i <= offerIdCounter; i++) {
            if (offers[i].offerCreator == _offerCreator) {
                offersByUser[index] = offers[i];
                index++;
            }
        }

        return offersByUser;
    }

    function createOffer(
        uint256 _listingId,
        uint256 _quantityOfferedForPurchase,
        uint256 _pricePerNFT,
        uint256 _offerExpireTime
    ) external whenNotPaused nonReentrant {
        NFTListing storage listing = NFTListings[_listingId];
        require(listing.listingStatus == 1, "Listing not active");
        require(
            _quantityOfferedForPurchase > 0 &&
                _quantityOfferedForPurchase <= listing.QuantityOnSale,
            "Invalid quantity of NFTs offered for purchase"
        );
        require(_pricePerNFT > 0, "Price per NFT must be greater than 0");
        require(
            _offerExpireTime > block.timestamp,
            "Offer expiration time must be in the future"
        );
        require(
            listing.NFTContractAddress != address(0),
            "Invalid NFT contract address"
        );
        require(
            IERC1155(listing.NFTContractAddress).isApprovedForAll(
                listing.seller,
                address(this)
            ),
            "Contract not approved to transfer NFTs"
        );

        IERC20 settlementToken = listing.tokenAdd;

        uint256 offerAmount = _quantityOfferedForPurchase * _pricePerNFT;
        if (offerAmount > 0) {
            if (settlementToken == IERC20(address(0x0))) {
                // Perform the MAAL transfer
                (bool success, ) = address(this).call{value: offerAmount}("");
                require(success, "MAAL transfer failed");
            } else {
                require(
                    settlementToken.balanceOf(msg.sender) >= offerAmount,
                    "Not enough balance"
                );
                require(
                    settlementToken.transferFrom(
                        msg.sender,
                        address(this),
                        offerAmount
                    ),
                    "Transfer to contract failed!"
                );
            }
        }

        uint256 offerId = ++offerIdCounter;
        Offer storage offer = offers[offerId];
        offer.offerId = offerId;
        offer.NFTContractAddress = listing.NFTContractAddress;
        offer.listingId = _listingId;
        offer.TokenId = listing.TokenId;
        offer.quantityOfferedForPurchase = _quantityOfferedForPurchase;
        offer.tokenAdd = settlementToken;
        offer.pricePerNFT = _pricePerNFT;
        offer.offerExpireTime = _offerExpireTime;
        offer.offerCreator = msg.sender;
        offer.isActive = true;
        offer.lockedValue = offerAmount;

        _offersByListing[_listingId][offerId] = offerId;
        NFTListings[_listingId].offers.push(offerId);

        emit OfferCreated(
            offerId,
            _listingId,
            listing.TokenId,
            _quantityOfferedForPurchase,
            settlementToken,
            _pricePerNFT,
            _offerExpireTime
        );
    }

    // Function to cancel an offer
    function cancelOffer(uint256 offerId) external {
        // Verify that the offer exists
        require(
            offers[offerId].offerCreator != address(0),
            "Offer does not exist"
        );
        // Verify that the offer has not been cancelled or completed
        require(
            offers[offerId].isActive,
            "Offer has already been cancelled or completed"
        );
        // Verify that the caller is the seller of the offer
        require(
            msg.sender == offers[offerId].offerCreator,
            "Only the seller can cancel the offer"
        );

        // Update the offer to indicate that it has been cancelled
        offers[offerId].isActive = false;

        uint256 refundAmnt = offers[offerId].lockedValue;
        IERC20 settlementToken = offers[offerId].tokenAdd;

        if (settlementToken == IERC20(address(0x0))) {
            require(
                address(this).balance >= refundAmnt,
                "Not enough balance in the contract!"
            );
            // Perform the MAAL transfer
            (bool success, ) = msg.sender.call{value: refundAmnt}("");
            require(success, "MAAL transfer failed");
        } else {
            require(
                settlementToken.balanceOf(address(this)) >=
                    offers[offerId].lockedValue,
                "Contract doesn't have enough balance for refund!"
            );
            require(
                settlementToken.transfer(
                    msg.sender,
                    offers[offerId].lockedValue
                ),
                "Refund failed!"
            );
        }

        // Emit an event to notify the frontend of the cancellation
        emit OfferCancelled(offerId);
    }

    // // Function to modify an offer
    // function modifyOffer(
    //     uint256 offerId,
    //     uint256 newPricePerNFT,
    //     uint256 newExpireTime
    // ) external {
    //     // Verify that the offer exists
    //     require(
    //         offers[offerId].offerCreator != address(0),
    //         "Offer does not exist"
    //     );
    //     // Verify that the offer has not been cancelled or completed
    //     require(
    //         offers[offerId].isActive,
    //         "Offer has already been cancelled or completed"
    //     );
    //     // Verify that the caller is the seller of the offer
    //     require(
    //         msg.sender == offers[offerId].offerCreator,
    //         "Only the offer creator can modify the offer"
    //     );

    //     if(newPricePerNFT > offers[offerId].pricePerNFT) {
    //         uint256 additionalAmnt = newPricePerNFT - offers[offerId].pricePerNFT;
    //     }

    //     // Update the offer with the new price
    //     offers[offerId].pricePerNFT = newPricePerNFT;
    //     offers[offerId].offerExpireTime = newExpireTime;

    //     // Emit an event to notify the frontend of the modification
    //     emit OfferModified(offerId, newPricePerNFT, newExpireTime);
    // }

    function acceptOffer(uint256 _offerId) external nonReentrant {
        Offer storage offer = offers[_offerId];
        NFTListing storage listing = NFTListings[offer.listingId];

        require(msg.sender == listing.seller, "Only seller can accept offers");
        require(offer.isActive == true, "Offer must be active");
        require(offer.offerExpireTime >= block.timestamp, "Offer has expired");

        IERC20 settlementToken = offer.tokenAdd;

        // Mark listing as sold
        listing.listingStatus = 2;

        // Mark offer as inactive
        offer.isActive = false;

        // Distribute fees
        uint256 platformFeeValue = (offer.lockedValue * platformFee) / 10000;
        uint256 royaltyFeeValue = (offer.lockedValue *
            collections[listing.collectionId].royaltyFee) / 10000;
        uint256 sellerValue = offer.lockedValue -
            platformFeeValue -
            royaltyFeeValue;

        uint256 combinedValue = platformFeeValue +
            royaltyFeeValue +
            sellerValue;
        address royaltyReceiver = collections[listing.collectionId]
            .walletForRoyalty;

        // Handle Transfers
        if (settlementToken == IERC20(address(0x0))) {
            require(
                address(this).balance >= combinedValue,
                "Not enough fund in the contract!"
            );
            // Transfer Platform fees to platform owner
            (bool platformFeeSuccess, ) = owner.call{value: platformFeeValue}(
                ""
            );
            require(platformFeeSuccess, "MAAL transfer failed");
            // Transfer Royalty to collection owner
            (bool royaltyFeeSuccess, ) = royaltyReceiver.call{
                value: royaltyFeeValue
            }("");
            require(royaltyFeeSuccess, "MAAL transfer failed");
            // Transfer the rest to the seller
            (bool sellerAmntSuccess, ) = listing.seller.call{
                value: sellerValue
            }("");
            require(sellerAmntSuccess, "MAAL transfer failed");
        } else {
            require(
                settlementToken.balanceOf(address(this)) >= combinedValue,
                "Not enough balance"
            );
            require(
                settlementToken.transfer(owner, platformFeeValue),
                "Failed to transfer platform fee"
            );
            require(
                settlementToken.transfer(royaltyReceiver, royaltyFeeValue),
                "Failed to transfer royalty fee"
            );
            require(
                settlementToken.transfer(listing.seller, sellerValue),
                "Failed to transfer seller value"
            );
        }

        // Determine if NFT is ERC721 or ERC1155
        bool isERC721 = _supportsERC721Interface(listing.NFTContractAddress);
        bool isERC1155 = _supportsERC1155Interface(listing.NFTContractAddress);

        if (isERC721) {
            // Transfer NFT from seller to buyer
            IERC721 NFTContract = IERC721(listing.NFTContractAddress);
            NFTContract.safeTransferFrom(
                listing.seller,
                offer.offerCreator,
                listing.TokenId
            );
        } else if (isERC1155) {
            // Transfer NFT from seller to buyer
            IERC1155 NFTContract = IERC1155(listing.NFTContractAddress);
            NFTContract.safeTransferFrom(
                listing.seller,
                offer.offerCreator,
                listing.TokenId,
                offer.quantityOfferedForPurchase,
                ""
            );
        }

        // Remove offer from listing's offer list
        uint256[] storage offerList = listing.offers;
        uint256 i;
        for (i = 0; i < offerList.length; i++) {
            if (offerList[i] == _offerId) {
                break;
            }
        }
        for (uint256 j = i; j < offerList.length - 1; j++) {
            offerList[j] = offerList[j + 1];
        }
        offerList.pop();

        // Emit event
        emit OfferAccepted(_offerId, offer.offerCreator);
    }

    /* buy NFT */

    function buyNFT(uint256 _listingId, uint256 _quantity)
        external
        nonReentrant
    {
        NFTListing storage listing = NFTListings[_listingId];

        require(listing.listingStatus == 1, "Listing is not active");
        require(
            listing.listingExpireTime >= block.timestamp,
            "Listing has expired"
        );
        require(
            _quantity > 0 && _quantity <= listing.QuantityOnSale,
            "Invalid quantity"
        );

        IERC20 settlementToken = listing.tokenAdd;
        address royaltyReceiver = collections[listing.collectionId]
            .walletForRoyalty;

        // Calculate the total purchase amount
        uint256 purchaseAmount = listing.PricePerNFT * _quantity;

        // Distribute fees
        uint256 platformFeeValue = (purchaseAmount * platformFee) / 10000;
        uint256 royaltyFeeValue = (purchaseAmount *
            collections[listing.collectionId].royaltyFee) / 10000;
        uint256 sellerValue = purchaseAmount -
            platformFeeValue -
            royaltyFeeValue;

        // Mark listing as sold if all tokens are sold
        if (_quantity == listing.QuantityOnSale) {
            listing.listingStatus = 2;
        } else {
            listing.QuantityOnSale -= _quantity;
        }

        // Handle Transfers
        if (settlementToken == IERC20(address(0x0))) {
            require(
                (msg.sender).balance >= purchaseAmount,
                "Not enough fund in your wallet!"
            );
            // Transfer Platform fees to platform owner
            (bool platformFeeSuccess, ) = owner.call{value: platformFeeValue}(
                ""
            );
            require(platformFeeSuccess, "Platform Fee transfer failed");
            // Transfer Royalty to collection owner
            (bool royaltyFeeSuccess, ) = royaltyReceiver.call{
                value: royaltyFeeValue
            }("");
            require(royaltyFeeSuccess, "Royalty transfer failed");
            // Transfer the rest to the seller
            (bool sellerAmntSuccess, ) = listing.seller.call{
                value: sellerValue
            }("");
            require(sellerAmntSuccess, "Seller amount transfer failed");
        } else {
            require(
                settlementToken.balanceOf(msg.sender) >= purchaseAmount,
                "Not enough balance"
            );
            require(
                settlementToken.transferFrom(
                    msg.sender,
                    owner,
                    platformFeeValue
                ),
                "Failed to transfer platform fee"
            );
            require(
                settlementToken.transferFrom(
                    msg.sender,
                    royaltyReceiver,
                    royaltyFeeValue
                ),
                "Failed to transfer royalty fee"
            );
            require(
                settlementToken.transferFrom(
                    msg.sender,
                    listing.seller,
                    sellerValue
                ),
                "Failed to transfer seller value"
            );
        }

        // Determine if NFT is ERC721 or ERC1155
        bool isERC721 = _supportsERC721Interface(listing.NFTContractAddress);
        bool isERC1155 = _supportsERC1155Interface(listing.NFTContractAddress);

        if (isERC721) {
            // Transfer NFT from seller to buyer
            IERC721 NFTContract = IERC721(listing.NFTContractAddress);
            NFTContract.safeTransferFrom(
                listing.seller,
                msg.sender,
                listing.TokenId
            );
        } else if (isERC1155) {
            // Transfer NFT from seller to buyer
            IERC1155 NFTContract = IERC1155(listing.NFTContractAddress);
            NFTContract.safeTransferFrom(
                listing.seller,
                msg.sender,
                listing.TokenId,
                _quantity,
                ""
            );
        }

        // Emit event
        emit NFTBought(_listingId, _quantity, msg.sender);
    }

    /**
        Admin functions
        -------------------------------------------------------------------
    **/

    /** 
        @notice recover any ERC20 token sent to the contract
        @param _token address of the token to recover
        @param _amount amount of the token to recover
    */
    function recoverToken(address _token, uint256 _amount)
        external
        whenPaused
        onlyOwner
    {
        IERC20(_token).transfer(address(msg.sender), _amount);
        emit TokenRecovery(_token, _amount);
    }

    /** 
        @notice recover any ERC721 token sent to the contract
        @param _NFTContract of the collection to recover
        @param _tokenId uint256 of the tokenId to recover
    */
    function recoverNFT(address _NFTContract, uint256 _tokenId)
        external
        whenPaused
        onlyOwner
    {
        IERC721 nft = IERC721(_NFTContract);
        nft.safeTransferFrom(address(this), address(msg.sender), _tokenId);
        emit NFTRecovery(_NFTContract, _tokenId);
    }

    /** 
        @notice recover any ERC721 token sent to the contract
        @param _NFTContract of the collection to recover
        @param _tokenId uint256 of the tokenId to recover
    */
    function recover1155NFT(
        address _NFTContract,
        uint256 _tokenId,
        uint256 _quantity
    ) external whenPaused onlyOwner {
        IERC1155 nft = IERC1155(_NFTContract);
        nft.safeTransferFrom(
            address(this),
            address(msg.sender),
            _tokenId,
            _quantity,
            ""
        );
        emit NFTRecovery(_NFTContract, _tokenId);
    }

    /** 
        @notice pause the marketplace
        @param _reason string of the reason for pausing the marketplace
    */
    function pauseMarketplace(string calldata _reason)
        external
        whenNotPaused
        onlyOwner
    {
        _pause();
        emit Pause(_reason);
    }

    /** 
        @notice unpause the marketplace
        @param _reason string of the reason for unpausing the marketplace
    */
    function unpauseMarketplace(string calldata _reason)
        external
        whenPaused
        onlyOwner
    {
        _unpause();
        emit Unpause(_reason);
    }

    /**
        Admin functions
        -------------------------------------------------------------------
    **/
}
