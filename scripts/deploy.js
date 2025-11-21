const { ethers } = require("hardhat");

async function main() {
  const ChainGallery = await ethers.getContractFactory("ChainGallery");
  const chainGallery = await ChainGallery.deploy();

  await chainGallery.deployed();

  console.log("ChainGallery contract deployed to:", chainGallery.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
