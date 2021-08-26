import fs from "fs";
import path from "path";
let hre = require("hardhat");
let chainId = 0;
let filePath = path.join(__dirname, `.data.json`);

async function getChainId() {
    chainId = await hre.network.provider.send("eth_chainId");
    chainId = Number(chainId);
    let _filePath = path.join(__dirname, `.data.${chainId}.json`);
    if (fs.existsSync(_filePath)) {
      filePath = _filePath;
    }
    console.log('filePath:', filePath);
  }

async function main() {
    console.log("============Start verify contract.============");
    await getChainId();

    // get deploy data from .data.json
    let rawdata = fs.readFileSync(filePath);
    let data = JSON.parse(rawdata.toString());

    // verify
    for (const ele of Object.keys(data)) {
        if(data[ele].verified){
            continue;
        }
        let addr = data[ele].address
        if(data[ele].upgraded) {
            addr = data[ele].upgradedAddress
        }
        if(!addr){
            continue;
        }
        console.log('verify:addr',ele, addr);
        await hre.run("verify:verify", {
            address: addr,
            constructorArguments: data[ele].constructorArgs,
        })
        data[ele].verified = true
    }

    // updata .data.json
    let content = JSON.stringify(data, null, 2);
    fs.writeFileSync(filePath, content);

    console.log("============Verify contract Done!============");
}

main();

