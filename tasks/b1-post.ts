import { task } from 'hardhat/config';
import {
  LensHub__factory,
  BtraxCollectModule__factory,
  ModuleGlobals__factory,
} from "../typechain-types";
import { PostDataStruct } from '../typechain-types/LensHub';
import { getAddrs, initEnv, waitForTx, ZERO_ADDRESS } from './helpers/utils';


task('bpost', 'publishes a b.trax post').setAction(async ({}, hre) => {
  const [governance, , user] = await initEnv(hre);
  const addrs = getAddrs();

  const btraxCollectModuleAddr = addrs['b.trax collect module'];
  const currencyAddress = addrs['currency'];

  const lensHub = LensHub__factory.connect(addrs['lensHub proxy'], governance);
  const moduleGlobals = ModuleGlobals__factory.connect(addrs['module globals'], governance)
  const btraxModule = BtraxCollectModule__factory.connect(addrs['b.trax collect module'], user);

  console.log('currency', await moduleGlobals.isCurrencyWhitelisted(currencyAddress));

  await waitForTx(lensHub.whitelistCollectModule(btraxCollectModuleAddr, true));

  const inputStruct: PostDataStruct = {
    profileId: 1,
    contentURI: 'https://ipfs.io/ipfs/Qmby8QocUU2sPZL46rZeMctAuF5nrCc7eR1PPkooCztWPz',
    collectModule: btraxCollectModuleAddr,
    collectModuleInitData: hre.ethers.utils.defaultAbiCoder.encode([
      'uint256', 'uint256', 'address', 'address', 'uint16', 'bool'
    ], [
      3, 1, currencyAddress, "0xEEA0C1f5ab0159dba749Dc0BAee462E5e293daaF", 10, false
    ]),
    referenceModule: ZERO_ADDRESS,
    referenceModuleInitData: [],
  };

  await waitForTx(lensHub.connect(user).post(inputStruct));
  console.log(await lensHub.getPub(1, 1));
  console.log(await btraxModule.getPublicationData(1, 1));
});


// abi.decode(data, (uint256, uint256, address, address, uint16, bool));

// "collectLimit": "100000",
//   "amount": {
//   "currency": "0xD40282e050723Ae26Aeb0F77022dB14470f4e011",
//     "value": "0.01"
// },
// "recipient": "0xEEA0C1f5ab0159dba749Dc0BAee462E5e293daaF",
//   "referralFee": 10.5,
//   "followerOnly": false
