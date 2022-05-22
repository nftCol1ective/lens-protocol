import { task } from 'hardhat/config';
import { LensHub__factory, BtraxCollectModule__factory } from '../typechain-types';
import { getAddrs, initEnv } from './helpers/utils';


task('bupdate-collect', 'collects a b.trax post').setAction(async ({}, hre) => {
  const [, , user] = await initEnv(hre);
  const addrs = getAddrs();
  const lensHub = LensHub__factory.connect(addrs['lensHub proxy'], user);

  const moduleAddress = await lensHub.getCollectModule(1, 1);
  const module = BtraxCollectModule__factory.connect(moduleAddress, user);

  let statics = await module.getStateData(1, 1);
  console.log(statics);

  await module.setOpened(1, 1);
  await module.updateUsed(1, 1, true);
  await module.updateDownloaded(1, 1);

  statics = await module.getStateData(1, 1);
  console.log(statics);
});
