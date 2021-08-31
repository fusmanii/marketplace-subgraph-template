// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Marketplace is ERC1155Holder, AccessControl, ReentrancyGuard {
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.AddressSet;
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");
  address payable public treasuryWallet;
  IERC20 stars;
  uint256 nextListingId = 0;
  uint256 listingFee = 0; //4 decimals

  struct Listing {
    address payable seller;
    address tokenAddress;
    uint256 tokenId;
    uint256 tokenAmount;
    uint256 price;
    bool isStarsListing;
  }

  struct Auction {
    address payable seller;
    address tokenAddress;
    uint256 tokenId;
    uint256 tokenAmount;
    uint256 startingStarsPrice;
    uint256 startingEthPrice;
    uint256 startTime;
    uint256 endTime;
    bool allowStarsBids;
    bool allowEthBids;
    Bid highestStarsBid;
    Bid highestEthBid;
  }

  struct Bid {
    address payable bidder;
    uint256 amount;
  }

  EnumerableSet.AddressSet private NFTs;

  mapping(uint256 => Listing) public listings;
  EnumerableSet.UintSet private listingIds;

  mapping(uint256 => Auction) public auctions;
  EnumerableSet.UintSet private auctionIds;

  event ListingCreated(
    address seller,
    address tokenAddress,
    uint256 tokenId,
    uint256 tokenAmount,
    uint256 price,
    uint256 listingId,
    bool isStarsListing
  );
  event ListingPriceChanged(uint256 listingId, uint256 newPrice);
  event ListingCancelled(uint256 listingId);
  event SaleMade(address buyer, uint256 listingId, uint256 amount);

  event AuctionCreated(
    address seller,
    address tokenAddress,
    uint256 tokenId,
    uint256 tokenAmount,
    uint256 startingStarsPrice,
    uint256 startingEthPrice,
    uint256 startTime,
    uint256 endTime,
    uint256 auctionId,
    bool allowStarsBids,
    bool allowEthBids
  );
  event BidPlaced(
    address bidder,
    uint256 auctionId,
    uint256 amount,
    bool isStarsBid
  );
  event AuctionClaimed(address winner, uint256 auctionId);
  event AuctionCancelled(uint256 auctionId);

  modifier onlyAdmin {
    require(hasRole(ROLE_ADMIN, msg.sender), "Sender is not admin");
    _;
  }

  /**
   * @dev Stores the Stars contract, and allows users with the admin role to
   * grant/revoke the admin role from other users. Stores treasury wallet.
   *
   * Params:
   * starsAddress: the address of the Stars contract
   * _admin: address of the first admin
   * _treasuryWallet: address of treasury wallet
   */
  constructor(
    address starsAddress,
    address _admin,
    address payable _treasuryWallet,
    address _NFTAddress
  ) {
    require(
      _treasuryWallet != address(0),
      "Treasury wallet cannot be 0 address"
    );
    _setupRole(ROLE_ADMIN, _admin);
    _setRoleAdmin(ROLE_ADMIN, ROLE_ADMIN);

    treasuryWallet = _treasuryWallet;
    stars = IERC20(starsAddress);

    NFTs.add(_NFTAddress);
  }

  //Allows contract to inherit both ERC1155Receiver and AccessControl
  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(ERC1155Receiver, AccessControl)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }

  //Get number of listings
  function getNumListings() external view returns (uint256) {
    return listingIds.length();
  }

  /**
   * @dev Get listing ID at index
   *
   * Params:
   * index: index of ID
   */
  function getListingIds(uint256 index) external view returns (uint256) {
    return listingIds.at(index);
  }

  /**
   * @dev Get listing correlated to index
   *
   * Params:
   * index: index of ID
   */
  function getListingAtIndex(uint256 index)
    external
    view
    returns (Listing memory)
  {
    return listings[listingIds.at(index)];
  }

  //Get number of auctions
  function getNumAuctions() external view returns (uint256) {
    return auctionIds.length();
  }

  /**
   * @dev Get auction ID at index
   *
   * Params:
   * index: index of ID
   */
  function getAuctionIds(uint256 index) external view returns (uint256) {
    return auctionIds.at(index);
  }

  /**
   * @dev Get auction correlated to index
   *
   * Params:
   * index: index of ID
   */
  function getAuctionAtIndex(uint256 index)
    external
    view
    returns (Auction memory)
  {
    return auctions[auctionIds.at(index)];
  }

  /**
   * @dev Create a new listing
   *
   * Params:
   * label: listing label
   * tokenAddress: address of token to list
   * tokenId: id of token
   * tokenAmount: number of tokens
   * price: listing price
   * isStarsListing: whether or not the listing is sold for Stars
   */
  function createListing(
    address tokenAddress,
    uint256 tokenId,
    uint256 tokenAmount,
    uint256 price,
    bool isStarsListing
  ) external nonReentrant() {
    require(NFTs.contains(tokenAddress), "Only  NFTs can be listed");

    IERC1155 token = IERC1155(tokenAddress);
    token.safeTransferFrom(msg.sender, address(this), tokenId, tokenAmount, "");
    uint256 listingId = generateListingId();
    listings[listingId] = Listing(
      payable(msg.sender),
      tokenAddress,
      tokenId,
      tokenAmount,
      price,
      isStarsListing
    );
    listingIds.add(listingId);

    emit ListingCreated(
      msg.sender,
      tokenAddress,
      tokenId,
      tokenAmount,
      price,
      listingId,
      isStarsListing
    );
  }

  function changeListingPrice(uint256 listingId, uint256 newPrice) external {
    Listing storage listing = listings[listingId];
    require(
      msg.sender == listing.seller || hasRole(ROLE_ADMIN, msg.sender),
      "Sender is not seller or admin"
    );

    listing.price = newPrice;

    emit ListingPriceChanged(listingId, newPrice);
  }

  /**
   * @dev Cancel a listing
   *
   * Params:
   * listingId: listing ID
   */
  function cancelListing(uint256 listingId) external {
    Listing storage listing = listings[listingId];
    require(
      msg.sender == listing.seller || hasRole(ROLE_ADMIN, msg.sender),
      "Sender is not seller or admin"
    );

    IERC1155 token = IERC1155(listing.tokenAddress);
    token.safeTransferFrom(
      address(this),
      listing.seller,
      listing.tokenId,
      listing.tokenAmount,
      ""
    );
    listingIds.remove(listingId);
    emit ListingCancelled(listingId);
  }

  /**
   * @dev Buy a token
   *
   * Params:
   * listingId: listing ID
   * amount: amount tokens to buy
   */
  function buyTokens(uint256 listingId, uint256 amount)
    external
    payable
    nonReentrant()
  {
    require(listingIds.contains(listingId), "Listing does not exist.");

    Listing storage listing = listings[listingId];

    require(listing.tokenAmount >= amount, "Not enough tokens remaining");

    uint256 fullAmount = listing.price.mul(amount);
    uint256 fee = fullAmount.mul(listingFee).div(10000);

    if (listing.isStarsListing) {
      if (fee > 0) {
        stars.safeTransferFrom(msg.sender, address(this), fee);
      }

      stars.safeTransferFrom(msg.sender, listing.seller, fullAmount.sub(fee));
    } else {
      require(msg.value == fullAmount, "Incorrect transaction value");

      listing.seller.transfer(fullAmount.sub(fee));
    }

    listing.tokenAmount -= amount;

    if (listing.tokenAmount == 0) {
      listingIds.remove(listingId);
    }

    IERC1155 token = IERC1155(listing.tokenAddress);
    token.safeTransferFrom(
      address(this),
      msg.sender,
      listing.tokenId,
      amount,
      ""
    );

    emit SaleMade(msg.sender, listingId, amount);
  }

  /**
   * @dev Create an auction
   *
   * Params:
   * label: auction label
   * tokenAddress: address of token
   * tokenId: token ID
   * tokenAmount: number of tokens the winner will get
   * startingStarsPrice: starting price for Stars bids
   * startingEthPrice: starting mprice for eth bids
   * startTime: auction start time
   * endTime: auction end time
   * allowStarsBids: whether or not Stars bids are allowed
   * allowEthBids: whether or not Eth bids are allowed
   *
   * Requirements:
   * allowStarsBids or allowEthBids is true
   */
  function createAuction(
    address tokenAddress,
    uint256 tokenId,
    uint256 tokenAmount,
    uint256 startingStarsPrice,
    uint256 startingEthPrice,
    uint256 startTime,
    uint256 endTime,
    bool allowStarsBids,
    bool allowEthBids
  ) external nonReentrant() {
    require(
      allowStarsBids || allowEthBids,
      "One of ETH bids or Stars bids must be allowed"
    );

    IERC1155 token = IERC1155(tokenAddress);
    token.safeTransferFrom(msg.sender, address(this), tokenId, tokenAmount, "");

    uint256 auctionId = generateAuctionId();
    auctions[auctionId] = Auction(
      payable(address(msg.sender)),
      tokenAddress,
      tokenId,
      tokenAmount,
      startingStarsPrice,
      startingEthPrice,
      startTime,
      endTime,
      allowStarsBids,
      allowEthBids,
      Bid(payable(address(msg.sender)), 0),
      Bid(payable(address(msg.sender)), 0)
    );
    auctionIds.add(auctionId);
    emit AuctionCreated(
      payable(address(msg.sender)),
      tokenAddress,
      tokenId,
      tokenAmount,
      startingStarsPrice,
      startingEthPrice,
      startTime,
      endTime,
      auctionId,
      allowStarsBids,
      allowEthBids
    );
  }

  /**
   * @dev Place in a bid and refund the previous highest bidder
   *
   * Params:
   * auctionId: auction ID
   * isStarsBid: true if bid is in Stars, false if it's in eth
   * amount: amount of bid
   *
   * Requirements:
   * Bid is higher than the previous highest bid of the same type
   */
  function placeBid(
    uint256 auctionId,
    bool isStarsBid,
    uint256 amount
  ) external payable nonReentrant() {
    Auction storage auction = auctions[auctionId];
    require(
      block.timestamp >= auction.startTime &&
        block.timestamp <= auction.endTime,
      "Cannot place bids at this time"
    );
    if (isStarsBid) {
      require(auction.allowStarsBids, "Auction does not accept Stars");
      require(
        amount > auction.highestStarsBid.amount &&
          amount > auction.startingStarsPrice,
        "Bid is too low"
      );
      stars.safeTransferFrom(msg.sender, address(this), amount);
      stars.safeTransfer(
        auction.highestStarsBid.bidder,
        auction.highestStarsBid.amount
      );
      auction.highestStarsBid = Bid(payable(address(msg.sender)), amount);
    } else {
      require(auction.allowEthBids, "Auction does not accept ether");
      require(
        amount > auction.highestEthBid.amount &&
          amount > auction.startingEthPrice,
        "Bid is too low"
      );
      require(amount == msg.value, "Amount does not match message value");
      auction.highestEthBid.bidder.transfer(auction.highestEthBid.amount);
      auction.highestEthBid = Bid(payable(address(msg.sender)), amount);
    }

    emit BidPlaced(msg.sender, auctionId, amount, isStarsBid);
  }

  /**
   * @dev End auctions and reward the winner without needing a price Oracle.
   * The caller chooses whether the Stars bid or Ether bid was higher.
   *
   * Params:
   * auctionId: auction ID
   * didStarsBidWin: whether or not the Stars bid won
   *
   * Requirements:
   * Auction is over
   * The auction supports bids of the winning bid type
   */
  function claimAuctionWithoutOracle(uint256 auctionId, bool didStarsBidWin)
    external
    onlyAdmin
    nonReentrant()
  {
    require(auctionIds.contains(auctionId), "Auction does not exist");
    Auction memory auction = auctions[auctionId];
    require(block.timestamp >= auction.endTime, "Auction is ongoing");
    address winner;

    if (didStarsBidWin) {
      require(auction.allowStarsBids, "Auction did not support Stars bids");
      winner = auction.highestStarsBid.bidder;
    } else {
      require(auction.allowEthBids, "Auction did not support Stars bids");
      winner = auction.highestEthBid.bidder;
    }

    IERC1155(auction.tokenAddress).safeTransferFrom(
      address(this),
      winner,
      auction.tokenId,
      auction.tokenAmount,
      ""
    );
    auctionIds.remove(auctionId);
    emit AuctionClaimed(winner, auctionId);
  }

  /**
   * @dev End auctions and reward the winner. If the auction supported both
   * Stars and eth bids, uses the oracle to determine who won
   *
   * Params:
   * auctionId: auction ID
   *
   * Requirements:
   * Price oracle is set if auction supports both Stars and Eth bids
   */
  function claimAuction(uint256 auctionId) external nonReentrant() {
    require(auctionIds.contains(auctionId), "Auction does not exist");
    Auction memory auction = auctions[auctionId];
    require(block.timestamp >= auction.endTime, "Auction is ongoing");
    address winner;

    if (auction.allowEthBids && auction.allowStarsBids) {
      winner = auction.highestStarsBid.bidder;
      auction.highestEthBid.bidder.transfer(auction.highestEthBid.amount);
    } else if (auction.allowEthBids) {
      winner = auction.highestEthBid.bidder;
    } else {
      winner = auction.highestStarsBid.bidder;
    }

    IERC1155(auction.tokenAddress).safeTransferFrom(
      address(this),
      winner,
      auction.tokenId,
      auction.tokenAmount,
      ""
    );
    auctionIds.remove(auctionId);
    emit AuctionClaimed(winner, auctionId);
  }

  /**
   * @dev Cancel auction and refund bidders
   *
   * Params:
   * auctionId: auction ID
   */
  function cancelAuction(uint256 auctionId) external nonReentrant() {
    require(auctionIds.contains(auctionId), "Auction does not exist");
    Auction memory auction = auctions[auctionId];

    require(
      msg.sender == auction.seller || hasRole(ROLE_ADMIN, msg.sender),
      "Sender is not seller or admin"
    );

    auction.highestEthBid.bidder.transfer(auction.highestEthBid.amount);

    IERC1155(auction.tokenAddress).safeTransferFrom(
      address(this),
      auction.seller,
      auction.tokenId,
      auction.tokenAmount,
      ""
    );

    stars.safeTransfer(
      auction.highestStarsBid.bidder,
      auction.highestStarsBid.amount
    );
    auctionIds.remove(auctionId);
    emit AuctionCancelled(auctionId);
  }

  //Generate ID for next listing
  function generateListingId() internal returns (uint256) {
    return nextListingId++;
  }

  //Generate ID for next auction
  function generateAuctionId() internal returns (uint256) {
    return nextListingId++;
  }

  //Withdraw ETH to treasury wallet
  function withdrawETH() external onlyAdmin {
    require(auctionIds.length() == 0, "Auctions are ongoing");
    treasuryWallet.transfer(address(this).balance);
  }

  //Withdraw Stars to treasury wallet
  function withdrawStars() external onlyAdmin {
    require(auctionIds.length() == 0, "Auctions are ongoing");
    stars.safeTransfer(treasuryWallet, stars.balanceOf(address(this)));
  }

  function addNFTAddress(address _NFTAddress) external onlyAdmin {
    NFTs.add(_NFTAddress);
  }

  function removeNFTAddress(address _NFTAddress) external onlyAdmin {
    NFTs.remove(_NFTAddress);
  }

  function setListingFee(uint256 _listingFee) external onlyAdmin {
    listingFee = _listingFee;
  }
}
