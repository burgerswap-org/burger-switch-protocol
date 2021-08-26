let BigNumber  = require("bignumber.js");

function test1() {
    let amount = '900000';
    let rewardRate = '1000000000000';
    let deno = '1000000000000000000';
    let res = new BigNumber(amount).multipliedBy(rewardRate).dividedBy(deno).toFixed();
    console.log('res:', res);
}

test1();