import { ethers, network } from "hardhat";
import fs from "fs";
import path from "path";
import {sleep} from "sleep-ts";
let chainId = 0;
let dataPath = path.join(__dirname, `.data.json`);
let callDataPath = path.join(__dirname, `.callData.json`);
let data: any = [
]


async function getChainId() {
  chainId = await network.provider.send("eth_chainId");
  chainId = Number(chainId);
  let _dataPath = path.join(__dirname, `.data.${chainId}.json`);
  if (fs.existsSync(_dataPath)) {
    dataPath = _dataPath;
  }
  let _callDataPath = path.join(__dirname, `.callData.${chainId}.json`);
  if (fs.existsSync(_callDataPath)) {
    callDataPath = _callDataPath;
  }
  console.log('dataPath:', dataPath);
  console.log('callDataPath:', callDataPath);
}

async function waitForMint(tx:any) {
  let result = null
  do {
    result = await ethers.provider.getTransactionReceipt(tx)
    await sleep(500)
  } while (result === null)
  await sleep(500)
}

function replaceData(search:any, src:any, target:any) {
  if(Array.isArray(src)) {
    for(let i in src) {
      if ((src[i]+'').indexOf(search) != -1) {
        src[i] = src[i].replace(src[i], target);
      }
    }
  } else if ((src+'').indexOf(search) != -1) {
    src = src.replace(src, target);
  }
  return src;
}


function updateCallData(contractName: string, address: string) {
  for (let k in data) {
    if (data[k].contractName == contractName && data[k].contractAddr == "") {
      data[k].contractAddr = address;
    }
    for (let i in data[k].args) {
      let v = "${" + contractName + ".address}";
      data[k].args[i] = replaceData(v, data[k].args[i], address);
    }
  }
}

async function updateArgsFromData() {
  if (fs.existsSync(dataPath)) {
    let rawdata = fs.readFileSync(dataPath);
    let _data = JSON.parse(rawdata.toString());
    for (let k in _data) {
      if (_data[k].address != "") {
        updateCallData(k, _data[k].address);
      }
    }
  }
}

async function call() {
  for (let k in data) {
    if (data[k].call && data[k].contractAddr != "" && data[k].contractName != "") {
      console.log(` =============== Call ${data[k].contractName}.${data[k].functionName} ...`)
      await sleep(100)
      let ins = await ethers.getContractAt(data[k].contractName, data[k].contractAddr)
      let tx = await ins[data[k].functionName](...data[k].args)
      // console.log(` =============== Call ${data[k].contractName}.${data[k].functionName} tx:`, tx)
      await waitForMint(tx.hash)
      console.log(` =============== Call ${data[k].contractName}.${data[k].functionName} txhash: `, tx.hash)
    }
  }
}

async function before() {
  await getChainId();
  if (fs.existsSync(callDataPath)) {
    let rawData = fs.readFileSync(callDataPath)
    data = JSON.parse(rawData.toString())
    await updateArgsFromData()
  }
  // console.log("====callData{====");
  // for (let k in data) {
  //   console.log(data[k])
  // }
  // console.log("====callData}====");
}

async function main() {
  await before();
  await call();
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
  