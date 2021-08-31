import { BigInt } from "@graphprotocol/graph-ts"
import {
  Marketplace,
  AuctionCancelled,
  AuctionClaimed,
  AuctionCreated,
  BidPlaced,
  ListingCancelled,
  ListingCreated,
  ListingPriceChanged,
  RoleAdminChanged,
  RoleGranted,
  RoleRevoked,
  SaleMade
} from "../generated/Marketplace/Marketplace"
import { Auction, Listing, Bid, Sale } from "../generated/schema"

export function handleAuctionCancelled(event: AuctionCancelled): void {
  let auction = Auction.load(event.params.auctionId.toString());

  if (auction) {
    auction.save();
  }
}

export function handleAuctionClaimed(event: AuctionClaimed): void {
  let auction = Auction.load(event.params.auctionId.toString());

  if (auction) {
    auction.winner = event.params.winner;
    auction.save();
  }
}

export function handleAuctionCreated(event: AuctionCreated): void {
  let auction = new Auction(event.params.auctionId.toString());

  auction.seller = event.params.seller;
  auction.tokenAddress = event.params.tokenAddress;
  auction.tokenId = event.params.tokenId;
  auction.tokenAmount = event.params.tokenAmount;
  auction.startingStarsPrice = event.params.startingStarsPrice;
  auction.startingEthPrice = event.params.startingEthPrice;
  auction.start = event.params.startTime;
  auction.end = event.params.endTime;
  auction.allowStarsBids = event.params.allowStarsBids;
  auction.allowEthBids = event.params.allowEthBids;

  auction.save();
}

export function handleBidPlaced(event: BidPlaced): void {
  
  let auction = Auction.load(event.params.auctionId.toString());

  if (auction) {
    let bid = new Bid(event.params.auctionId.toString() + "-" + event.transaction.hash.toHex());
    bid.bidder = event.params.bidder; 
    bid.amount = event.params.amount;
    bid.auction = auction.id; 
    
    bid.save()
  }
}

export function handleListingCancelled(event: ListingCancelled): void {

  let listing = Listing.load(event.params.listingId.toString());
  
  if (listing) {
    listing.save();
  }

}

export function handleListingCreated(event: ListingCreated): void {
  let listing = new Listing(event.params.listingId.toString());

  listing.seller = event.params.seller;
  listing.tokenAddress = event.params.tokenAddress;
  listing.tokenId = event.params.tokenId;
  listing.tokenAmount = event.params.tokenAmount;
  listing.price = event.params.price;
  listing.isStarsListing = event.params.isStarsListing;

  listing.save();

}

export function handleListingPriceChanged(event: ListingPriceChanged): void {
  let listing = Listing.load(event.params.listingId.toString()); 

  if (listing) {
    listing.price = event.params.newPrice;
    listing.save();
  }
}

export function handleRoleAdminChanged(event: RoleAdminChanged): void {}

export function handleRoleGranted(event: RoleGranted): void {}

export function handleRoleRevoked(event: RoleRevoked): void {}

export function handleSaleMade(event: SaleMade): void {

  let sale = new Sale(event.params.listingId.toString() + "-" + event.transaction.hash.toHex())
  
  sale.buyer = event.params.buyer;
  sale.listingID = event.params.listingId; 
  sale.tokenAmount = event.params.amount;

  sale.save();
}
