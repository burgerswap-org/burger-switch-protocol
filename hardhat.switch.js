let fs = require("fs");
let path = require("path");
const USER_HOME = process.env.HOME || process.env.USERPROFILE

function switchConfig(chainName) {
  console.log('switchConfig: ', chainName);
  let filePath = path.join(USER_HOME+'/.hardhat.data.'+ chainName +'.json');
  let targetPath = path.join(USER_HOME+'/.hardhat.data.json');
  if (fs.existsSync(filePath)) {
    fs.copyFileSync(filePath, targetPath);
    return;
  }
  filePath = path.join(__dirname, `.hardhat.data.${chainName}.json`);
  targetPath = path.join(__dirname, `.hardhat.data.json`);
  if (fs.existsSync(filePath)) {
    fs.copyFileSync(filePath, targetPath);
    return;
  }
}


function main() {
  switchConfig(process.argv[2]);
}

main();