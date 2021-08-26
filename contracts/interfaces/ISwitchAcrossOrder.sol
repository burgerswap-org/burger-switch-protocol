// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

interface ISwitchAcrossOrder {
    function feeWallet() external view returns (address);
    function totalSlideOfToken(address _token) external view returns (uint);
    function collectSlide(address _token) external returns (uint amount);
    function inSn() external view returns (uint);
    function outSn() external view returns (uint);
    function inSnMapOrders(uint _sn) external view returns (
        address user,
        uint nonce
    );
    function outSnMapOrders(uint _sn) external view returns (
        address user,
        uint nonce
    );

    function userInOrderNonce(address _user) external view returns (uint);
    function userOutOrderNonce(address _user) external view returns (uint);
    function transferIn(address _to, address[] memory _tokens, uint[] memory _values) external payable;
    function transferOut(address _from, address[] memory _tokens, uint[] memory _values, bytes memory _signature) external;
    function queryWithdraw(address _token, uint _value) external view returns (uint);
}
