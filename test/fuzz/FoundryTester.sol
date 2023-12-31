// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./Tester.sol";
import "./Asserts.sol";

/// @title Foundry-specific tester contract
/// @author Antonio Viggiano <@agfviggiano>
/// @notice Serves as a foundry-especific tester contract to be fuzzed
/// @dev Inherits from a base `Tester` contract that exposes all functions to be fuzzed. In invariant tests, foundry requires all target contracts to be deployed on the `setUp` function inherited from the `Test` contract from `forge-std`, which is why `_deploy` is called there, and the foundry-specific `FoundryTester` tester contract receives the target contracts as constructor arguments. In addition, it exposes a `invariantFailed` public view method that will be checked against in order to validate if any assertion failed from the `Asserts` contract.
contract FoundryTester is Asserts, Tester {
    bool public failed;
    string public message;

    constructor(ERC20Mock _token1, ERC20Mock _token2, UniswapV2Pair _pair, UniswapV2Factory _factory) {
        token1 = _token1;
        token2 = _token2;
        pair = _pair;
        factory = _factory;
    }

    function gt(uint256 a, uint256 b, string memory reason) internal override {
        if (!(a > b)) {
            failed = true;
            message = reason;
        }
    }

    function gte(uint256 a, uint256 b, string memory reason) internal override {
        if (!(a >= b)) {
            failed = true;
            message = reason;
        }
    }

    function lt(uint256 a, uint256 b, string memory reason) internal override {
        if (!(a < b)) {
            failed = true;
            message = reason;
        }
    }

    function lte(uint256 a, uint256 b, string memory reason) internal override {
        if (!(a <= b)) {
            failed = true;
            message = reason;
        }
    }

    function eq(uint256 a, uint256 b, string memory reason) internal override {
        if (!(a == b)) {
            failed = true;
            message = reason;
        }
    }

    function t(bool b, string memory reason) internal override {
        if (!(b)) {
            failed = true;
            message = reason;
        }
    }
}
