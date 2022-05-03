// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./LocoMeta.sol";
import "./Pancakeswap.sol";

contract TokenMigrator is Ownable, ReentrancyGuard {

    using SafeMath for uint256;

    ERC20 token;
    LocoMetaV2 v2;

    mapping (address => bool) public _claimed;

    constructor(ERC20 _old, LocoMetaV2 _v2) ReentrancyGuard() {
        token = ERC20(_old);
        v2 = LocoMetaV2(_v2);
    }

    function checkBalance() public view returns(uint256) {
        return token.balanceOf(msg.sender);
    }

    function swapTokens() public returns(bool) {
        uint256 userBalance = token.balanceOf(msg.sender);
        require(userBalance > 0, "Insufficient balance");
        bool completed = token.transferFrom(msg.sender,address(0x000000000000000000000000000000000000dEaD), userBalance);

        if(completed) {
            v2.migrateToNewTokens(msg.sender, userBalance);
        }

        return completed;
    }

}