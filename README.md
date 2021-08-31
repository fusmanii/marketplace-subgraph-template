1. What does the smart contract do? 

Marketplace allows an admin to create auctions and generate individual listings. This is done by transferring an appropriate amount of tokens from the admin to the contract and initializing the type of auction/listing (such as its duration, whether it uses stars or ether, etc.) -> createListing() , createAuction(). 

Once an auction or a listing has been created, users have the ability to buy tokens from existing listings (buyTokens()) or bid on existing auctions (placeBid()). This can be done using stars or ether depending on the auction/listing. This transfers the payment from the user to the contract. For listings, the corresponding tokens are transferred to the user. For auctions, the user has to wait until the duration of the auction has completed to either receive their bid money back or receive their tokens (claimAuction()). 

2. Deploying the contract.

Once the contract has been compiled and tested and functions as normal, it is ready to be deployed to a live network. This way, we can access an instance of the contract in a shared staging environemnt. This contract was deployed to the Rinkeby test network. 

In the **deploy.js** file in the **scripts** directory, an instance of the contract is created to be deployed. Using `ethers.getContractFactory('Marketplace')`, an instance of the Marketplace contract is created. Then, using `Marketplace.deploy(stars, admin, treasury, nft)` with the appropriate addresses for the stars, admin, treasure, and nft parameters, deployment is started. This returns a Promise that resolves to a Contract. 

To deploy to the rinkeby network, we need to configure the **hardhat.config.js** file. Using an API from Alchemy, Infura, or any other Ethereum node, as well as the private key for your live network, we can add a network entry into *module.exports*. Finally, running `npx hardhat run scripts/deploy.js --network rinkeby` in terminal should deploy the contract and return its deployed address. (Note: it is good practice to save the deployed address in a text file in the current directory as it will be used many times during the verification and testing processes.)

3. Contract verification

After deployment, verifying source code on Etherscan is effective to test and interact with your deployed contract. In order to do this, some libraries need to be installed by running `npm install --save-dev @nomiclabs/hardhat-etherscan` and adding this statement `require("@nomiclabs/hardhat-etherscan");` into the **hardhat.config.js** file. 

Since the constructor of the Marketplace contract has a long argument list, it can be useful to include an **arguments.js** file that exports the respective arguments using *module.exports*. In this file, the addresses for the stars token, admin, treasury account, and nft token are exported. 

Finally, the module can be loaded and the contract is verified on Etherscan by running: `npx hardhat verify --constructor-args arguments.js DEPLOYED_CONTRACT_ADDRESS --network rinkeby`.

4. Interacting with the contract. 

Once the contract is verified on Etherscan, we can interact with it using its address. After connecting to Web3 using the Metamask extension wallet and before being able to place bids or create an auction, each token used needs to be approved. First, the user/admin needs to hold the tokens in their wallet. Then, approval can be done by going to each token's respective address on Etherscan and invoking the *approve* method on each for use by the contract. This is why it is so important to have the address of the deployed contract saved. 

Finally, we can write to the contract by populating the fields of the method calls. For the *createAuction()* method, we can put in the token address of the NFT token, the ID of the token, the token amount, the price for the Stars token, the price in ether, the start and end times, as well as whether or not the auction accepts Stars/Ether bids. Once populated, we can write to the contract and an auction instance will be created on the live network which we can later query using our subgraph.

5. Functionality of the subgraph. 

The data from this contract is indexed based on the subgraph description. Once the subgraph manifest is created, queries can be completed using GraphQl. 

To begin the subgraph manifest, it is essential to [intialize the graph using the address of the deployed Marketplace contract](https://thegraph.com/docs/developer/create-subgraph-hosted#from-an-existing-contract). 

Once initialization is complete, the [subgraph.yaml](https://thegraph.com/docs/developer/create-subgraph-hosted#the-subgraph-manifest) file can be edited. Here, it is important to make sure that the address of the contract is correct and that the start block of where the queries should begin is updated. (Note: if start block is not specified, the queries will take a really long time to appear. You can updae the start block by viewing your transaction on etherscan, obtaining the block number, and creating an entry on `dataSources.source.startBlock`). 

Here, is a snippet of code from the **subgraph.yaml** file: 
```
dataSources:
    source:
      address: "0xfB80C874b1C8C94414653E93E855Ab00c8743f5f"
      abi: Marketplace
      startBlock: 9098376

``` 
Under dataSoures.source, the address of the contract, the abi of the contract, and its start block are all defined.

After editing and checking the **subgraph.yaml** file, [schemas for different entities are defined in the schema.graphql file](https://thegraph.com/docs/developer/create-subgraph-hosted#the-graphql-schema). In this file, we defined entities for an auction type, a listing type, a bid type, and a sale type. It is important to note how these entities are related. For example, there is a one-to-many relationship between an auction and a bid; an auction can have multiple bids associated with it. Thus, when defining an auction type, it is important to create a bid field that references the bid entity. This is shown below:  

```
type Auction @entity {
  id: ID!
  seller: Bytes!
  tokenAddress: Bytes!
  tokenId: BigInt!
  tokenAmount: BigInt!
  startingEthPrice: BigInt!
  startingStarsPrice: BigInt!
  start: BigInt!
  end: BigInt!
  allowStarsBids: Boolean!
  allowEthBids: Boolean!
  winner: Bytes
  bids: [Bid!] @derivedFrom(field: "auction")
}

type Bid @entity {
  id: ID!
  bidder: Bytes!
  amount: BigInt!
  auction: Auction!
}
```
Here, the entity fields for each type are defined by the built-in scalar types supported in the [GraphQL API](https://thegraph.com/docs/developer/create-subgraph-hosted#built-in-scalar-types). The `!` operator next to the types indicate whether that field is required or not. In this example, we can see how the *bids* field in the Auction entity is derived from the *auction* field in the Bid entity. As each bid can have only one auction associated with it, this snippet of code puts all the bids of that particular Auction into an array within the *bids* field of that Auction.

Once all entites are defined, we can run `npm run codegen` to update the **schema.ts** file.

The last thing to do to make a functional subgraph is to [create mappings which transform Ethereum data to entites from our schema in the mapping.ts file](https://thegraph.com/docs/developer/create-subgraph-hosted#writing-mappings). For each event created from our Marketplace contract, there is a corresponding event handl er in the **mappings.ts** file. In this event handler, we want to create and/or update any appropriate entities. For example, for the AuctionCreated event in our contract, there is a corresponding handleAuctionCreated event handler in the **mapping.ts** file. In this handler, we want to create an Auction entity and populate the entity fields with the corresponding event parameters from our contract as shown below: 

```
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
```
Here, an auction entity is created using the **auctionId* parameter from the emitted contract event. This becomes the ID for the entity. The rest of the fields of the auction entity are populated in a similar way. Using the appropriate parameters from the emitted contract event, we can assign them to the fields of the auction entity. Once populated, we can store the entity on the graph store by using the `.save()` keyword. In this way, the data from an emitted event that is stored on the blockchain can be transformed into an entity that makes queries possible.

After this stage is completed, we can deploy the subgraph we created to subgraph studio using `graph deploy --studio marketplace`. Queries can be now completed in the studio quickly as the subgraph syncs frequently after any event is emitted from the contract. 