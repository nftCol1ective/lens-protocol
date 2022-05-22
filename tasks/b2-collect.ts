import { task } from 'hardhat/config';
import { LensHub__factory, CollectNFT__factory, Currency__factory } from '../typechain-types';
import { getAddrs, initEnv, waitForTx } from './helpers/utils';
import { defaultAbiCoder } from "ethers/lib/utils";


task('bcollect', 'collects a b.trax post').setAction(async ({}, hre) => {
  const [, , user] = await initEnv(hre);
  const addrs = getAddrs();
  const lensHub = LensHub__factory.connect(addrs['lensHub proxy'], user);
  const currency = Currency__factory.connect(addrs['currency'], user);

  await currency.mint(user.address, 10);

  await currency.approve(addrs['b.trax collect module'], 10);
  const allowance = await currency.allowance(user.address, addrs['b.trax collect module']);
  console.log('allowance', allowance.toString());

  const data = defaultAbiCoder.encode(
    ['address', 'uint256'],
    [addrs['currency'], 1]
  );
  await waitForTx(lensHub.collect(1, 1, data));

  const collectNFTAddr = await lensHub.getCollectNFT(1, 1);
  const collectNFT = CollectNFT__factory.connect(collectNFTAddr, user);

  const publicationContentURI = await lensHub.getContentURI(1, 1);
  const totalSupply = await collectNFT.totalSupply();
  const ownerOf = await collectNFT.ownerOf(1);
  const collectNFTURI = await collectNFT.tokenURI(1);

  console.log(`Collect NFT total supply (should be 1): ${totalSupply}`);
  console.log(
    `Collect NFT owner of ID 1: ${ownerOf}, user address (should be the same): ${user.address}`
  );
  console.log(
    `Collect NFT URI: ${collectNFTURI}, publication content URI (should be the same): ${publicationContentURI}`
  );
});
