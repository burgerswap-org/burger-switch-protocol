// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface IAddressWhitelist {
    function check(address account) external view returns (bool);
    function add(address account) external;
    function remove(address account) external;
}
