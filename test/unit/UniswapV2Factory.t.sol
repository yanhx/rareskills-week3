// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console, stdError} from "forge-std/Test.sol";
import {UniswapV2Factory} from "../../src/UniswapV2Factory.sol";
import {UniswapV2Pair} from "../../src/UniswapV2Pair.sol";

contract UniswapV2FactoryTest is Test {
    UniswapV2Factory uniswapV2Factory;
    address public _feeToSetter = address(30);

    address pairAddress;
    UniswapV2Pair pair;

    address[] public addresses = [
        address(0x1000000000000000000000000000000000000000),
        address(0x2000000000000000000000000000000000000000),
        address(0x3000000000000000000000000000000000000000),
        address(0x4000000000000000000000000000000000000000)
    ];

    function setUp() public {
        uniswapV2Factory = new UniswapV2Factory(_feeToSetter);
        // console.log("uniswapV2Factory");
        // console.log(address(uniswapV2Factory));

        pairAddress = uniswapV2Factory.createPair(addresses[0], addresses[1]);
        pair = UniswapV2Pair(pairAddress);
    }

    function test_CreatPair() public {
        // create pair
        bytes memory bytecode =
            abi.encodePacked(type(UniswapV2Pair).creationCode, abi.encode(addresses[0], addresses[1]));
        bytes32 salt = keccak256(abi.encodePacked(addresses[0], addresses[1]));
        console.log("abi.encodePacked(addresses[0],addresses[1])");
        console.logBytes(abi.encodePacked(addresses[0], addresses[1]));
        console.log("salt");
        console.logBytes32(salt);

        address precompileAddress = getAddress(bytecode, salt, address(uniswapV2Factory));
        console.log(precompileAddress);
        console.log(pairAddress);
        assertEq(precompileAddress, pairAddress);

        //  UniswapV2Pair test
        assertEq(pair.name(), "Uniswap V2");
        assertEq(pair.symbol(), "UNI-V2");
        assertEq(pair.factory(), address(uniswapV2Factory));
        assertEq(pair.token0(), addresses[0]);
        assertEq(pair.token1(), addresses[1]);

        // getPair test
        assertEq(uniswapV2Factory.getPair(addresses[0], addresses[1]), precompileAddress);
        assertEq(uniswapV2Factory.getPair(addresses[1], addresses[0]), precompileAddress);

        // allPairs test
        assertEq(uniswapV2Factory.allPairs(0), precompileAddress);
        assertEq(uniswapV2Factory.allPairsLength(), 1);
    }

    function test_CreatePairMultipleTokens() public {
        address tokenPair0 = uniswapV2Factory.createPair(addresses[0], addresses[2]);
        address tokenPair1 = uniswapV2Factory.createPair(addresses[1], addresses[3]);

        assertEq(uniswapV2Factory.getAllPairLength(), 3);
        assertEq(uniswapV2Factory.getAllPairsIndex(1), tokenPair0);
        assertEq(uniswapV2Factory.getAllPairsIndex(2), tokenPair1);
        assertEq(UniswapV2Pair(tokenPair0).token0(), addresses[0]);
        assertEq(UniswapV2Pair(tokenPair0).token1(), addresses[2]);
        assertEq(UniswapV2Pair(tokenPair1).token0(), addresses[1]);
        assertEq(UniswapV2Pair(tokenPair1).token1(), addresses[3]);
    }

    function test_CreatePairIdenticalTokens() public {
        vm.expectRevert(bytes("UniswapV2: IDENTICAL_ADDRESSES"));
        uniswapV2Factory.createPair(addresses[0], addresses[0]);
    }

    function test_CreatePairInvalidToken() public {
        vm.expectRevert(bytes("UniswapV2: ZERO_ADDRESS"));
        uniswapV2Factory.createPair(address(0), addresses[1]);

        vm.expectRevert(bytes("UniswapV2: ZERO_ADDRESS"));
        uniswapV2Factory.createPair(addresses[0], address(0));
    }

    function test_CreatePairDuplicatePair() public {
        vm.expectRevert(bytes("UniswapV2: PAIR_EXISTS"));
        uniswapV2Factory.createPair(addresses[0], addresses[1]);
    }

    // 2. Compute the address of the contract to be deployed
    // NOTE: _salt is a random number used to create an address
    function getAddress(bytes memory bytecode, bytes32 _salt, address factory) internal view returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), factory, _salt, keccak256(bytecode)));

        console.log("hash");
        console.logBytes32(hash);

        return address(uint160(uint256(hash)));
    }
}
