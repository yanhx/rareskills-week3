// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console, stdError} from "forge-std/Test.sol";

import {ERC20Mock} from "lib/solady/ext/woke/ERC20Mock.sol";
import {UniswapV2Factory} from "../../src/UniswapV2Factory.sol";
import {UniswapV2Pair} from "../../src/UniswapV2Pair.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract AddLiquidityTest is Test {
    address public _feeToSetter = address(0x30);
    address public pairAddress;
    address public lockAddress = address(0x0);
    address public zeroAddress = address(0x0);

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    ERC20Mock tokenA;
    ERC20Mock tokenB;
    // reorder tokenA tokenB by address
    ERC20Mock public token0;
    ERC20Mock public token1;

    UniswapV2Pair public uniswapV2Pair;
    UniswapV2Factory uniswapV2Factory;

    uint256 constant INIT_TOKEN_AMT = 100000e18;

    function setUp() public {
        tokenA = new ERC20Mock('TOKENA','TA', 18);
        tokenB = new ERC20Mock('TOKENB','TB', 18);

        tokenA.mint(alice, INIT_TOKEN_AMT);
        tokenB.mint(alice, INIT_TOKEN_AMT);

        uniswapV2Factory = new UniswapV2Factory(_feeToSetter);
        pairAddress = uniswapV2Factory.createPair(address(tokenA), address(tokenB));
        uniswapV2Pair = UniswapV2Pair(pairAddress);
        (token0, token1) = getOrderERC20Mock(tokenA, tokenB);
        vm.startPrank(alice);
        tokenA.approve(pairAddress, type(uint256).max);
        tokenB.approve(pairAddress, type(uint256).max);
        vm.stopPrank();

        tokenA.mint(pairAddress, INIT_TOKEN_AMT);
        tokenB.mint(pairAddress, INIT_TOKEN_AMT);
        uniswapV2Pair.mint(address(this));
    }

    function test_MintWithApproval(
        uint256 tokenAInput,
        uint256 tokenBInput,
        uint256 tokenAInputMin,
        uint256 tokenBInputMin
    ) external {
        tokenAInput = bound(tokenAInput, 1001, INIT_TOKEN_AMT);
        tokenBInput = bound(tokenBInput, 1001, INIT_TOKEN_AMT);
        tokenAInputMin = bound(tokenAInputMin, 0, Math.min(tokenAInput, tokenBInput));
        tokenBInputMin = bound(tokenBInputMin, 0, Math.min(tokenAInput, tokenBInput));

        uint256 oldBalanceA = tokenA.balanceOf(pairAddress);
        uint256 oldBalanceB = tokenB.balanceOf(pairAddress);
        uint256 oldProduct = oldBalanceA * oldBalanceB;
        vm.startPrank(alice);
        uniswapV2Pair.mintWithApproval(alice, tokenAInput, tokenBInput, tokenAInputMin, tokenBInputMin);

        uint256 newBalanceA = tokenA.balanceOf(pairAddress);
        uint256 newBalanceB = tokenB.balanceOf(pairAddress);
        uint256 newProduct = newBalanceA * newBalanceB;
        vm.stopPrank();
        assert(oldProduct <= newProduct);
    }

    function test_SwapExactInForOut(uint256 exactAmountIn) external {
        exactAmountIn = bound(exactAmountIn, 2, INIT_TOKEN_AMT);
        //amountOutMin = bound(amountOutMin, exactAmountIn, exactAmountIn);
        uint256 oldBalanceA = tokenA.balanceOf(pairAddress);
        uint256 oldBalanceB = tokenB.balanceOf(pairAddress);
        uint256 oldProduct = oldBalanceA * oldBalanceB;
        vm.startPrank(alice);
        uniswapV2Pair.swapExactInForOut(false, exactAmountIn, 0, alice);
        uint256 newBalanceA = tokenA.balanceOf(pairAddress);
        uint256 newBalanceB = tokenB.balanceOf(pairAddress);
        uint256 newProduct = newBalanceA * newBalanceB;
        vm.stopPrank();
        assert(oldProduct <= newProduct);
    }

    function getOrderERC20Mock(ERC20Mock _tokenA, ERC20Mock _tokenB)
        private
        view
        returns (ERC20Mock _token0, ERC20Mock _token1)
    {
        (address token0Address, address token1Address) = address(_tokenA) < address(tokenB)
            ? (address(_tokenA), address(_tokenB))
            : (address(_tokenB), address(_tokenA));
        return (ERC20Mock(token0Address), ERC20Mock(token1Address));
    }
}
