// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

import './modules/Configable.sol';
import './libraries/SafeMath.sol';
import './modules/Initializable.sol';

contract SwitchFarmQuery is Configable, Initializable{
    using SafeMath for uint;
    address public farm;

    function initialize() public initializer {
        owner = msg.sender;
    }

    function configure(address _farm) external onlyDev {
        farm = _farm;
    }

}