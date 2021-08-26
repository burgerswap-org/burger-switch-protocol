// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

import './modules/Configable.sol';
import './modules/Initializable.sol';

contract AddressWhiteList is Initializable, Configable {
    mapping(address => bool) public whiteList;

    function check(address account) external view returns (bool) {
        require(account != address(0), "Invalid address");
        return whiteList[account];
    }

    function add(address account) external onlyDev {
        require(account != address(0), "Invalid address");
        whiteList[account] = true;
    }

    function remove(address account) external onlyDev {
        require(account != address(0), "Invalid address");
        whiteList[account] = false;
    }
}
