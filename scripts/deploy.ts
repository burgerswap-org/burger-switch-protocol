import { ethers, network } from "hardhat";
import fs from "fs";
import path from "path";
let chainId = 0;
let filePath = path.join(__dirname, `.data.json`);
let data: any = {
  SwitchTreasury: {
    address: "",
    constructorArgs: [],
    deployed: false,
    verified: false
  },
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

function updateConstructorArgs(contractName: string, address: string) {
  for (let k in data) {
    for (let i in data[k].constructorArgs) {
      let v = "${" + contractName + ".address}";
      if (data[k].constructorArgs[i] == v) {
        data[k].constructorArgs[i] = address;
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
        updateConstructorArgs(k, data[k].address);
      }
    }
  }
}

async function deployContract(contractName: string, value: any) {
  if (data[contractName].deployed) {
    console.log(`Deploy contract ${contractName} exits: "${data[contractName].address}",`)
    return;
  }
  console.log('Deploy contract...', contractName, value)
  const Factory = await ethers.getContractFactory(contractName);
  let ins = await Factory.deploy(...value.constructorArgs);
  await ins.deployed();
  data[contractName].address = ins.address;
  data[contractName].deployed = true;
  data[contractName].verified = false;
  console.log(`Deploy contract ${contractName} new: "${ins.address}",`)
  updateConstructorArgs(contractName, ins.address);
}

async function deploy() {
  console.log("============Start to deploy project's contracts.============");
  for (let k in data) {
    await deployContract(k, data[k])
  }
  console.log("======================Deploy Done!.=====================");
}


async function init() {

}

async function after() {
  let content = JSON.stringify(data, null, 2);
  fs.writeFileSync(filePath, content);
}

async function main() {
  await before();
  await deploy();
  await init();
  await after();
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });