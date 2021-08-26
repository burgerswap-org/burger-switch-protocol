const { ethers, upgrades, network } = require("hardhat");
import {sleep} from "sleep-ts";
import fs from "fs";
import path from "path";
let chainId = 0;
let filePath = path.join(__dirname, `.data.json`);
let data: any = {
  "SwitchTreasury": {
    "address": "",
    "constructorArgs": [
    ],
    "upgradeArgs": [
		],
    "upgradedAddress": "",
    "deployed": false,
    "upgraded": false,
    "verified": true
  }
};

async function getChainId() {
  chainId = await network.provider.send("eth_chainId");
  chainId = Number(chainId);
  let _filePath = path.join(__dirname, `.data.${chainId}.json`);
  if (fs.existsSync(_filePath)) {
    filePath = _filePath;
  }
  console.log('filePath:', filePath);
}

function updateUpgradeArgsArgs(contractName: string, address: string) {
  for (let k in data) {
    for (let i in data[k].upgradeArgs) {
      let v = "${" + contractName + ".address}";
      if (data[k].upgradeArgs[i] == v) {
        data[k].upgradeArgs[i] = address;
      }
    }
  }
}

async function before() {
  await getChainId();
  if (fs.existsSync(filePath)) {
    let rawdata = fs.readFileSync(filePath);
    data = JSON.parse(rawdata.toString());
    for (let k in data) {
      if (data[k].address != "") {
        updateUpgradeArgsArgs(k, data[k].address);
      }
    }
  }
}

async function after() {
  let content = JSON.stringify(data, null, 2);
  fs.writeFileSync(filePath, content);
}


async function deployContract(contractName: string, value: any) {
  // Deploying
  if (data[contractName].deployed) {
    console.log(`Deploy contract ${contractName} exits: "${data[contractName].address}",`)
    return;
  }
  // console.log('deploy...')
  await sleep(100);
  const Factory = await ethers.getContractFactory(contractName);
  const ins = await upgrades.deployProxy(Factory, data[contractName].upgradeArgs);
  await ins.deployed();
  data[contractName].address = ins.address;
  data[contractName].deployed = true;
  data[contractName].upgraded = true;
  data[contractName].verified = false;
  console.log(`Deploy contract ${contractName} new: "${ins.address}",`)
  updateUpgradeArgsArgs(contractName, ins.address);
}

async function upgradeContract(contractName: string, value: any) {
  // Upgrading
  if(!data[contractName].deployed || !data[contractName].address || data[contractName].upgraded) {
    return
  }
  // console.log('upgrade...', data[contractName].address)
  const Factory = await ethers.getContractFactory(contractName);
  const ins = await upgrades.upgradeProxy(data[contractName].address, Factory);
  data[contractName].address = ins.address;
  data[contractName].deployed = true;
  data[contractName].upgraded = true;
  data[contractName].verified = false;
  data[contractName].upgradedAddress = ins.address
  console.log(`Upgrade contract ${contractName} : ${ins.address}`)
}

async function deploy() {
  console.log("============Start to deploy project's contracts.============");
  for (let k in data) {
    try {
      await deployContract(k, data[k])
    } catch(e) {
      console.error('deployContract except', k, e)
    }
  }
  console.log("======================Deploy Done!.=====================");
}


async function upgrade() {
  console.log("============Start to upgrade project's contracts.============");
  for (let k in data) {
    try {
      await upgradeContract(k, data[k])
    } catch(e) {
      console.error('upgradeContract except', k, e)
    }
  }
  console.log("======================Upgrade Done!.=====================");
}



async function main() {
  await before();
  await deploy();
  await upgrade();
  await after();
}

main();
