const { ethers } = require("ethers");
const hre = require("hardhat");

async function main() {
  //const admin = await ethers.utils.getAddress('0x9d6C5Ba61C6348878623E90ba0934fa8Cd58169C');
  //const stars = await ethers.utils.getAddress('0xF37c8A532AE6B024E0942d0a922A330800C166Ab');
  //const nft = await ethers.utils.getAddress('0x1D4519D4aAdF25BEC5C03C34FF661D9487FA2aAf');

  const Marketplace = await hre.ethers.getContractFactory("Marketplace");
  const marketplace = await Marketplace.deploy(
    "0xF37c8A532AE6B024E0942d0a922A330800C166Ab",
    "0x9d6C5Ba61C6348878623E90ba0934fa8Cd58169C",
    "0x9d6C5Ba61C6348878623E90ba0934fa8Cd58169C",
    "0x1D4519D4aAdF25BEC5C03C34FF661D9487FA2aAf"
  );

  await marketplace.deployed();

  console.log("Marketplace deployed to:", marketplace.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
