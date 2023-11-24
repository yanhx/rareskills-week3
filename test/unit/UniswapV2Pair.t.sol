// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";

import {ERC20Mock} from "lib/solady/ext/woke/ERC20Mock.sol";
import {UniswapV2Factory} from "../../src/UniswapV2Factory.sol";
import {UniswapV2Pair} from "../../src/UniswapV2Pair.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ud, unwrap, UD60x18} from "@prb/math/src/UD60x18.sol";

contract UniswapV2PairTest is Test {
    address public _feeToSetter = address(0x30);
    address public pairAddress;
    address public lockAddress = address(0x0);
    address public zeroAddress = address(0x0);

    ERC20Mock tokenA;
    ERC20Mock tokenB;
    // reorder tokenA tokenB by address
    ERC20Mock public token0;
    ERC20Mock public token1;

    UniswapV2Pair public uniswapV2Pair;
    UniswapV2Factory uniswapV2Factory;

    uint256 constant INIT_TOKEN_AMT = 100000e18;

    // test events
    //
    event Sync(uint112 reserve0, uint112 reserve1);
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        tokenA = new ERC20Mock('TOKENA','TA', 18);
        tokenB = new ERC20Mock('TOKENB','TB', 18);
        tokenA.mint(address(this), INIT_TOKEN_AMT);
        tokenB.mint(address(this), INIT_TOKEN_AMT);

        uniswapV2Factory = new UniswapV2Factory(_feeToSetter);
        pairAddress = uniswapV2Factory.createPair(address(tokenA), address(tokenB));
        uniswapV2Pair = UniswapV2Pair(pairAddress);
        console.log("pairAddress", pairAddress);
        (token0, token1) = getOrderERC20Mock(tokenA, tokenB);
    }

    function assertBlockTimestampLast(uint256 timestamp) public {
        (,, uint32 lastBlockTimestamp) = uniswapV2Pair.getReserves();

        assertEq(timestamp, lastBlockTimestamp);
    }

    function assertCumulativePrices(uint256 price0, uint256 price1) public {
        assertEq(price0, uniswapV2Pair.price0CumulativeLast(), "unexpected cumulative price 0");
        assertEq(price1, uniswapV2Pair.price1CumulativeLast(), "unexpected cumulative price 1");
    }

    function assertPairReserves(uint256 _reserve0, uint256 _reserve1) public {
        (uint112 reserve0, uint112 reserve1,) = uniswapV2Pair.getReserves();
        assertEq(reserve0, _reserve0);
        assertEq(reserve1, _reserve1);
    }

    /**
     * Test functions
     *     1:test_Mint()
     *     2:test_AddLiquidity()
     *     3:test_SwapNormalCases()
     *     4:test_SwapCasesWithFees()
     *     5:test_SwapToken0AndCheck()
     *     6:test_SwapToken1AndCheck()
     *     7:test_burn()
     *     8:test_burnReceivedAllTokens()
     *     9:test_TAWP()
     *     10:test_CalculateExpectOutputAmountWithFee()
     */

    /**
     *   https://book.getfoundry.sh/forge/cheatcodes, check the event
     * math points
     *
     * test  init mint， transfer 1  token and 4 token, for the first time
     */
    function test_Mint() public {
        uint256 token0transferAmount = 1 * 10 ** token0.decimals();
        uint256 token1transferAmount = 4 * 10 ** token1.decimals();

        token0.transfer(pairAddress, token0transferAmount);
        token1.transfer(pairAddress, token1transferAmount);

        uint256 expectedLiquidity = Math.sqrt(token0transferAmount * token1transferAmount);
        vm.expectEmit(address(pairAddress));

        // for the first mint, should lock  MINIMUM_LIQUIDITY forever
        emit Transfer(address(0), lockAddress, uniswapV2Pair.MINIMUM_LIQUIDITY());
        // transfer LP to the caller
        uint256 actualLiquidity = expectedLiquidity - uniswapV2Pair.MINIMUM_LIQUIDITY();
        emit Transfer(address(0), address(this), actualLiquidity);

        emit Sync(uint112(token0.balanceOf(pairAddress)), uint112(token1.balanceOf(pairAddress)));

        // first mint, amount0 and amount1 equal the corresponding token transfer amount
        emit Mint(address(this), token0.balanceOf(pairAddress), uint112(token1.balanceOf(pairAddress)));

        uint256 liquidity = uniswapV2Pair.mint(address(this));

        // check the Liquidity amount and reserves
        assertEq(uniswapV2Pair.balanceOf(lockAddress), uniswapV2Pair.MINIMUM_LIQUIDITY());
        assertEq(uniswapV2Pair.totalSupply(), expectedLiquidity);
        assertEq(uniswapV2Pair.balanceOf(address(this)), actualLiquidity);
        assertEq(liquidity, actualLiquidity);

        assertEq(token0.balanceOf(pairAddress), token0transferAmount);
        assertEq(token1.balanceOf(pairAddress), token1transferAmount);

        assertPairReserves(token0transferAmount, token1transferAmount);
    }

    /**
     * test cases:
     *   after initing the pool,  test the following actions includingc normal and expections cases
     *
     *
     *    the related Math formula
     *    1. how to calculate the liqudity?
     *          uint expectedLiquidity = Math.sqrt(token0transferAmount * token1transferAmount);
     *          for the first time, should lock  MINIMUM_LIQUIDITY(10 ** 3), so the received lp = expectedLiquidity - MINIMUM_LIQUIDITY
     *          for the following actions, the received lp = expectedLiquidity
     *
     *    2. What's the effects of using the geometric mean.
     *         2.1 This formula ensures that the value of a liquidity pool share at any time is essentially independent of the ratio
     *     at which liquidity was initially deposited.
     *         (For the uniswap_v1,the value of a liquidity pool share was dependent on the ratio
     *         at which liquidity was initially deposited, which was fairly arbitrary, especially since there
     *         was no guarantee that that ratio reflected the true price.)
     *
     *         TODO questions, seems this situation not test,how to do this specifical case
     *         2.2 but this desgin have one situation: the minimum quantity of liquidity pool shares ((1e-18 pool shares) is worth so much that
     *             it becomes infeasible for small liquidity providers to provide any liquidity.  ???
     *
     *
     *         but the desgin supply a possible:if one attacker donate
     *
     *    3. why store the MINIMUM_LIQUIDITY forever?
     *         1. prevent the situation, the minimum quantity of liquidity pool shares worth so much, that small liquidity providers to provide any liquidity.
     */
    function test_AddLiquidity() public {
        // init mint,
        uint256[2] memory addAmounts = [1 * 10 ** token0.decimals(), 4 * 10 ** token1.decimals()];
        uint256 expectedLiquidity = Math.sqrt(addAmounts[0] * addAmounts[1]);
        addLiquidity(addAmounts[0], addAmounts[1]);
        assertEq(uniswapV2Pair.balanceOf(address(this)), expectedLiquidity - uniswapV2Pair.MINIMUM_LIQUIDITY());
        uint256 firstLPAmount = uniswapV2Pair.balanceOf(address(this));
        console.log(firstLPAmount);

        // add liquidity after mint
        // normal
        // points
        /**
         * 1. calculate the liquidity
         *     2. the more token, how to deal with?
         */
        /**
         * 2. how many shares will mint while adding liquidity
         *         s = (dx/X) T=  (dy/Y) T
         */
        // 1999999999999999000 + 2000000000000000000

        // after initing the pool, add liquidity again,
        uint256[2] memory addAmounts2 = [1 * 10 ** token0.decimals(), 4 * 10 ** token1.decimals()];
        uint256 expectedLiquidity2 = Math.sqrt(addAmounts2[0] * addAmounts2[1]);
        addLiquidity(addAmounts2[0], addAmounts2[1]);
        assertEq(uniswapV2Pair.balanceOf(address(this)), expectedLiquidity2 + firstLPAmount);
        // console.log(uniswapV2Pair.balanceOf(address(this)));
        // the lp token are not propratation to the received pair tokens, of there are more pair token, how to deal with it, use sync()
        //

        // Exception test
        // uint[2] memory addAmounts3 = [1*10**tokenA.decimals(),0];
        // tokenA.transfer(pairAddress,addAmounts3[0]);
        // tokenB.transfer(pairAddress,addAmounts3[1]);
        // vm.expectRevert(bytes("UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED"));
        // UniswapV2Pair(pairAddress).mint(address(this));

        uint256[2] memory addAmounts4 = [0, 1 * 10 ** token0.decimals()];
        token0.transfer(pairAddress, addAmounts4[0]);
        token1.transfer(pairAddress, addAmounts4[1]);
        vm.expectRevert(bytes("UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED"));
        UniswapV2Pair(pairAddress).mint(address(this));
    }

    function test_MintWithReserve() public {
        token0.transfer(address(uniswapV2Pair), 1 ether);
        token1.transfer(address(uniswapV2Pair), 1 ether);
        uint256 l1 = uniswapV2Pair.mint(address(this));

        token0.transfer(address(uniswapV2Pair), 2 ether);
        token1.transfer(address(uniswapV2Pair), 2 ether);
        uint256 l2 = uniswapV2Pair.mint(address(this));

        assertPairReserves(3 ether, 3 ether);
        assertEq(uniswapV2Pair.balanceOf(address(this)), l1 + l2);
        assertEq(uniswapV2Pair.totalSupply(), l1 + l2 + uniswapV2Pair.MINIMUM_LIQUIDITY());
    }

    /**
     * Swap test:
     *
     *
     *     todo
     *     /expect test
     */

    //  problem:  [1, 5, 10, 1662497915624478906], my calculated resut is: (10*1)*1e18/(5+1) = 1666666666666666666
    //  given the pool, the swapAmount of token0, check the output Amount of token1 is right
    function test_SwapNormalCases() public {
        uint64[4][7] memory arrays_test = [
            [1, 5, 10, 1662497915624478906],
            [1, 10, 5, 453305446940074565],
            [2, 5, 10, 2851015155847869602],
            [2, 10, 5, 831248957812239453],
            [1, 10, 10, 906610893880149131],
            [1, 100, 100, 987158034397061298],
            [1, 1000, 1000, 996006981039903216]
        ];
        for (uint256 i = 0; i < arrays_test.length; i++) {
            uint256[2] memory liqudity =
                [(arrays_test[i][1] * uint256(1e18)), uint256(arrays_test[i][2]) * uint256(1e18)];
            uint256 swapAmount = uint256(arrays_test[i][0]) * uint256(1e18);
            uint256 expectedOutputAmount1 = arrays_test[i][3];
            console.log(swapAmount);
            // vm.expectRevert(bytes("UniswapV2: K"));
            SwapTest(swapAmount, liqudity, 0, expectedOutputAmount1);
            // rebuild the pool address
            uniswapV2Factory = new UniswapV2Factory(_feeToSetter);
            pairAddress = uniswapV2Factory.createPair(address(tokenA), address(tokenB));
            uniswapV2Pair = UniswapV2Pair(pairAddress);
            console.log("pairAddress", pairAddress);
            (token0, token1) = getOrderERC20Mock(tokenA, tokenB);
        }
    }

    // same toke swap and same toke return.
    // 1/2/3 give the inputAmount, calculate the outputAmout
    // 4 given the  outputAmout, calculate the inputAmount
    function test_SwapCasesWithFees() public {
        uint64[4][4] memory arrays_test = [
            // [outputAmount, token0Amount, token1Amount, inputAmount]
            [997000000000000000, 5, 10, 1], // given amountIn, amountOut = floor(amountIn * .997)
            [997000000000000000, 10, 5, 1],
            [997000000000000000, 5, 5, 1],
            [1, 5, 5, 1003009027081243732] // given amountOut, amountIn = ceiling(amountOut / .997)
        ];
        for (uint256 i = 0; i < arrays_test.length; i++) {
            uint256[2] memory liqudity = [(arrays_test[i][1] * 1e18), uint256(arrays_test[i][2]) * 1e18];

            uint256 swapAmount = i < 3 ? uint256(arrays_test[i][3]) * uint256(1e18) : arrays_test[i][3];
            uint256 expectedOutputAmount0 = i < 3 ? arrays_test[i][0] : uint256(arrays_test[i][0]) ** uint256(1e18);
            SwapTest(swapAmount, liqudity, expectedOutputAmount0, 0);

            // rebuild the pool address
            uniswapV2Factory = new UniswapV2Factory(_feeToSetter);
            pairAddress = uniswapV2Factory.createPair(address(tokenA), address(tokenB));
            uniswapV2Pair = UniswapV2Pair(pairAddress);
            console.log("pairAddress", pairAddress);
            (token0, token1) = getOrderERC20Mock(tokenA, tokenB);
        }

        // test:amountIn = ceiling(amountOut / .997)
        uint256 result = Math.ceilDiv(10 ** 21, 997);
        console.log(result);
    }

    function test_SwapToken0AndCheck() public {
        uint256[2] memory liqudity = [uint256(5 * 1e18), uint256(10 * 1e18)];
        addLiquidity(liqudity[0], liqudity[1]);
        uint256 swapAmount = 1e18;
        // also a quesiton, can not figure out how to calculate the result
        uint256 expectedOutputAmount = 1662497915624478906; //(liqudity[1]*swapAmount)/(swapAmount+liqudity[0]) 1666666666666666666 1662497915624478906
        token0.transfer(pairAddress, swapAmount);

        // pair transfer the token1 to the this address
        emit Transfer(pairAddress, address(this), expectedOutputAmount);
        // Sync the balance0 and balance1
        emit Sync(uint112(swapAmount + liqudity[0]), uint112(liqudity[1] - expectedOutputAmount));

        // check the swap event
        emit Swap(pairAddress, swapAmount, 0, 0, expectedOutputAmount, address(this));

        uniswapV2Pair.swap(0, expectedOutputAmount, address(this));
        (uint112 _reserve0, uint112 _reserve1,) = uniswapV2Pair.getReserves();

        // check all kinds of balance
        assertEq(_reserve0, liqudity[0] + swapAmount);
        assertEq(_reserve1, liqudity[1] - expectedOutputAmount);

        assertEq(token0.balanceOf(pairAddress), liqudity[0] + swapAmount);
        assertEq(token1.balanceOf(pairAddress), liqudity[1] - expectedOutputAmount);

        uint256 totalSupplyToken0 = token0.totalSupply();
        uint256 totalSupplyToken1 = token1.totalSupply();
        assertEq(token0.balanceOf(address(this)), totalSupplyToken0 - liqudity[0] - swapAmount);
        assertEq(token1.balanceOf(address(this)), totalSupplyToken1 - liqudity[1] + expectedOutputAmount);
    }

    // just the opposite of the test_SwapToken0AndCheck
    function test_SwapToken1AndCheck() public {
        uint256[2] memory liqudity = [uint256(5 * 1e18), uint256(10 * 1e18)];
        addLiquidity(liqudity[0], liqudity[1]);
        uint256 swapAmount = uint256(1e18);
        // also a quesiton, can not figure out how to calculate the result
        uint256 expectedOutputAmount = 453305446940074565;
        token1.transfer(pairAddress, swapAmount);

        // pair transfer the token1 to the this address
        emit Transfer(pairAddress, address(this), expectedOutputAmount);

        // Sync the balance0 and balance1
        emit Sync(uint112(liqudity[1] - expectedOutputAmount), uint112(swapAmount + liqudity[0]));

        // check the swap event
        emit Swap(pairAddress, 0, swapAmount, 0, expectedOutputAmount, address(this));

        uniswapV2Pair.swap(expectedOutputAmount, 0, address(this));
        (uint112 _reserve0, uint112 _reserve1,) = uniswapV2Pair.getReserves();

        // // check all kinds of balance
        assertEq(_reserve0, liqudity[0] - expectedOutputAmount);
        assertEq(_reserve1, liqudity[1] + swapAmount);

        assertEq(token0.balanceOf(pairAddress), liqudity[0] - expectedOutputAmount);
        assertEq(token1.balanceOf(pairAddress), liqudity[1] + swapAmount);

        uint256 totalSupplyToken0 = token0.totalSupply();
        uint256 totalSupplyToken1 = token1.totalSupply();
        assertEq(token0.balanceOf(address(this)), totalSupplyToken0 - liqudity[0] + expectedOutputAmount);
        assertEq(token1.balanceOf(address(this)), totalSupplyToken1 - liqudity[1] - swapAmount);
    }

    // hints: because the MINIMUM_LIQUIDITY,received token0 and token1 will decrease 1000 TODO
    // TODO,. TEST: which scenario will received all LP. how to receive all token0 and token1
    // if after burn lp,  the left lp is greater than MINIMUM_LIQUIDITY, this scenario the burner will receve all token
    function test_burn() public {
        // init the pool
        uint256[2] memory liqudity = [uint256(3 * 1e18), uint256(3 * 1e18)];
        addLiquidity(liqudity[0], liqudity[1]);

        // burn the liquidity
        // first step: transfer the lp to the pairAddress
        uint256 expectedReceivedLiquidity = Math.sqrt(liqudity[0] * liqudity[1]) - uniswapV2Pair.MINIMUM_LIQUIDITY();
        uniswapV2Pair.transfer(pairAddress, expectedReceivedLiquidity);
        // second step: execute the burn function

        // pair transfer the transfered liquidity to the zero address
        emit Transfer(pairAddress, zeroAddress, expectedReceivedLiquidity);
        // pair transfer the token0 and token1 to the test addres, because the MINIMUM_LIQUIDITY, 1000(token0)*1000(token1) lock forever
        emit Transfer(pairAddress, address(this), liqudity[0] - 1000);
        emit Transfer(pairAddress, address(this), liqudity[1] - 1000);

        // Sync the balance0 and balance1, the minium balance
        emit Sync(uint112(1000), uint112(1000));

        // check the swap event
        emit Burn(pairAddress, liqudity[0] - 1000, liqudity[0] - 1000, address(this));

        uniswapV2Pair.burn(address(this));

        // // check all kinds of balance
        assertEq(uniswapV2Pair.balanceOf(address(this)), 0);
        assertEq(uniswapV2Pair.totalSupply(), uniswapV2Pair.MINIMUM_LIQUIDITY());

        // at least left the minium amount of token0 and token1
        assertEq(token0.balanceOf(pairAddress), 1000);
        assertEq(token1.balanceOf(pairAddress), 1000);

        // check token0 and token1 balance for testAddress
        uint256 totalSupplyToken0 = token0.totalSupply();
        uint256 totalSupplyToken1 = token1.totalSupply();

        assertEq(token0.balanceOf(address(this)), totalSupplyToken0 - 1000);
        assertEq(token1.balanceOf(address(this)), totalSupplyToken1 - 1000);
    }

    function test_burnReceivedAllTokens() public {
        // guarantee the MINIMUM_LIQUIDITY exists
        test_burn();
        console.log(" guarantee the MINIMUM_LIQUIDITY exists");
        uint256[2] memory liqudity = [uint256(3 * 1e18), uint256(3 * 1e18)];
        addLiquidity(liqudity[0], liqudity[1]);

        // burn the liquidity
        // first step: transfer the lp to the pairAddress
        uint256 expectedReceivedLiquidity = Math.sqrt(liqudity[0] * liqudity[1]);
        uniswapV2Pair.transfer(pairAddress, expectedReceivedLiquidity);
        // second step: execute the burn function

        // pair transfer the transfered liquidity to the zero address
        emit Transfer(pairAddress, zeroAddress, expectedReceivedLiquidity);
        // pair transfer the token0 and token1 to the test addres, because the MINIMUM_LIQUIDITY, 1000(token0)*1000(token1) lock forever
        emit Transfer(pairAddress, address(this), liqudity[0]);
        emit Transfer(pairAddress, address(this), liqudity[1]);

        // Sync the balance0 and balance1, the minium balance
        emit Sync(uint112(1000), uint112(1000));

        // check the swap event
        emit Burn(pairAddress, liqudity[0], liqudity[0], address(this));

        uniswapV2Pair.burn(address(this));

        // // check all kinds of balance
        assertEq(uniswapV2Pair.balanceOf(address(this)), 0);
        assertEq(uniswapV2Pair.totalSupply(), uniswapV2Pair.MINIMUM_LIQUIDITY());

        // at least left the minium amount of token0 and token1
        assertEq(token0.balanceOf(pairAddress), 1000);
        assertEq(token1.balanceOf(pairAddress), 1000);

        // check token0 and token1 balance for testAddress
        uint256 totalSupplyToken0 = token0.totalSupply();
        uint256 totalSupplyToken1 = token1.totalSupply();

        assertEq(token0.balanceOf(address(this)), totalSupplyToken0 - 1000);
        assertEq(token1.balanceOf(address(this)), totalSupplyToken1 - 1000);
    }

    function test_TAWP() public {
        uint256[2] memory liqudity = [3 * 10 ** token0.decimals(), 3 * 10 ** token1.decimals()];
        addLiquidity(liqudity[0], liqudity[1]);
        (uint256 price0CumulativeLast0, uint256 price1CumulativeLast0, uint32 blockTimestampStart) =
            uniswapV2Pair.getReserves();

        vm.warp(blockTimestampStart + 1); // mint the next block
        uniswapV2Pair.sync(); // sync, calculated the elasped time

        // first call the _update( sync after addLiquidity,sync will take the time to the TAMP's calculation )
        (uint256 price0, uint256 price1) = calculatePrice(liqudity[0], liqudity[1]);
        assertEq(uniswapV2Pair.price0CumulativeLast(), price0);
        assertEq(uniswapV2Pair.price1CumulativeLast(), price1);
        assertEq(blockTimestampStart, 1);

        // second call the_update(swap), the price should based on the last block's price
        uint256 swapAmount = 3 * 10 ** token0.decimals();
        token0.transfer(pairAddress, swapAmount);
        vm.warp(blockTimestampStart + 10); // mint the next block
        uint256 expectedOutputAmount1 = 1 * 10 ** token0.decimals();
        uniswapV2Pair.swap(0, expectedOutputAmount1, address(this)); // swap to a new price eagerly instead of syncing
        (,, uint32 blockTimestampAfterSwap) = uniswapV2Pair.getReserves();
        assertEq(uniswapV2Pair.price0CumulativeLast(), price0 * 10);
        assertEq(uniswapV2Pair.price1CumulativeLast(), price1 * 10);
        assertEq(blockTimestampAfterSwap, blockTimestampStart + 10);

        // third call the _update
        vm.warp(blockTimestampStart + 20); // mint the next block
        uniswapV2Pair.sync(); // sync, calculated the elasped time

        (uint256 price0Second, uint256 price1Second) =
            calculatePrice(liqudity[0] + swapAmount, liqudity[1] - expectedOutputAmount1);
        (uint256 price0CumulativeLast3, uint256 price1CumulativeLast3, uint32 blockTimestampThirdUpdate) =
            uniswapV2Pair.getReserves();
        assertEq(uniswapV2Pair.price0CumulativeLast(), price0 * 10 + price0Second * 10);
        assertEq(uniswapV2Pair.price1CumulativeLast(), price1 * 10 + price1Second * 10);
        assertEq(blockTimestampThirdUpdate, blockTimestampStart + 20);

        // According to the TAMP, calculating the price
        // from blockTimestampStart =>blockTimestampStart+20
        uint256 price0For20seconds =
            (price0CumulativeLast3 - price0CumulativeLast0) / (blockTimestampStart + 20 - blockTimestampStart);
        uint256 price1For20seconds =
            (price1CumulativeLast0 - price1CumulativeLast3) / (blockTimestampStart + 20 - blockTimestampStart);
        console.log("priceFo20seconds", price0For20seconds);
        console.log("price1For20seconds", price1For20seconds);

        // questions:
        // how to use? which protocols use?
        // how to prevent the manipulation by using TAWP.
        // the cost of attack. how to attack?
    }

    function addLiquidity(uint256 token0Amount, uint256 token1Amount) private {
        token0.transfer(pairAddress, token0Amount);
        token1.transfer(pairAddress, token1Amount);
        UniswapV2Pair(pairAddress).mint(address(this));
    }

    function SwapTest(
        uint256 swapAmount,
        uint256[2] memory liqudity,
        uint256 expectedOutputAmount0,
        uint256 expectedOutputAmount1
    ) private {
        addLiquidity(liqudity[0], liqudity[1]);
        token0.transfer(pairAddress, swapAmount);
        uniswapV2Pair.swap(expectedOutputAmount0, expectedOutputAmount1, address(this));
    }

    /**
     * 1. calculate expectedOutputAmount1
     *       how many dy while swaping dx?
     *       dx=  x*dy / y + dx
     *       dy = y*dx/ (x+ dx)
     *
     *     For the test case:[1, 5, 10, 1662497915624478906], which means pool has token0:5*1e18 and token1:10*1e18, one want swap 1*1e18 token0 to token1
     *     By using the formula:dy = y*dx/ (x+ dx) nomatter using the solidty bulit-in operations or UD60x18 operations. both of the result is:1666666666666666666
     *
     *     if the swap don't consider the fee, the result can passed. 8333333333333333333(10000000000000000000-1666666666666666666)*6000000000000000000 > 50000000000000000000000000000000000000
     *
     *     if the swap consider the fee, so the actual ouputAmount should less than the above result.
     *     Because uniswap use the below formula to check,and  if get actual amount1In, which involved many operations and become very complex.
     *         uint256 balance0Adjusted = balance0 * 1000 - amount0In * 3;
     *         uint256 balance1Adjusted = balance1 * 1000 - amount1In * 3;
     *         (balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * _reserve1 * (1000 ** 2)
     *
     *     This function just use brute force to calculate the expectoutputAmount when consider the fee
     */
    function test_CalculateExpectOutputAmountWithFee() public {
        // the init pool
        uint256[2] memory liqudity = [uint256(5 * 1e18), uint256(10 * 1e18)];

        // dy = y*dx/ (x+ dx)
        uint256 token0Amount = 1 * 1e18;
        uint256 expectedOutputAmount1 = (liqudity[1] * token0Amount) / (liqudity[0] + token0Amount);
        console.log("my result for token0Amount:", expectedOutputAmount1);

        // use 60*18 to calculate
        UD60x18 x = ud(liqudity[0]);
        UD60x18 y = ud(liqudity[1]);
        UD60x18 dx = ud(token0Amount);
        UD60x18 result = (y.mul(dx)).div(dx.add(x));
        console.log("use UD60x18 to calculate result", unwrap(result));
        // calcauting balance0*balance1  after transfer token0 for token0Amount and par transfer token1 for expectedOutputAmount1
        console.log(
            "balance0*balance1 after transfer", (liqudity[1] - expectedOutputAmount1) * (liqudity[0] + token0Amount)
        );

        // test swap
        addLiquidity(liqudity[0], liqudity[1]);
        token0.transfer(pairAddress, token0Amount);
        vm.expectRevert(bytes("UniswapV2: K")); //if consider the fee, my result should decrease some number.
        uniswapV2Pair.swap(0, expectedOutputAmount1, address(this));

        // after transfer token0
        uint256 afterBalance0 = liqudity[0] + token0Amount;
        // when consider the fee,should derease how many number to satisfy the consideraton of fee
        uint256 howmanyNumber;
        // uint afterBalance1 = liqudity[1] - (expectedOutputAmount1-howmanyNumber);

        // after transfer token0,consider the fee
        uint256 balance0Adjusted = afterBalance0 * 1000 - token0Amount * 3;

        // uint256 balance1Adjusted = (liqudity[1] - (expectedOutputAmount1-howmanyNumber)) * 1000;

        howmanyNumber = 4168751042187700; // consider the gas limit, from this number begin to calculate
        while (
            balance0Adjusted * ((liqudity[1] - (expectedOutputAmount1 - howmanyNumber)) * 1000)
                <= (liqudity[0] * liqudity[1]) * ((1000 ** 2))
        ) {
            // gap:1495831248957812240
            howmanyNumber++;
            // console.log("howmanynumber",howmanyNumber);
        }
        console.log("expect howmanynumber", howmanyNumber);
        console.log(expectedOutputAmount1 - howmanyNumber);
        uniswapV2Pair.swap(0, expectedOutputAmount1 - howmanyNumber, address(this));
    }

    // reorder address
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

    function calculatePrice(uint256 amount0, uint256 amount1) private view returns (uint256 price0, uint256 price1) {
        console.log("amount1/amount0", amount1 / amount0);
        return (unwrap(ud(amount1) / ud(amount0)), unwrap(ud(amount0) / ud(amount1)));
    }

    function test_Others() public view {
        console.log("type(uint112).max", type(uint112).max);
        console.log("type(uint256).max", type(uint256).max);

        // uMAX_UD60x18 / uUNIT
        // 1e18
        console.log(1e18);
        console.log(1e18);
        console.log("uint256 max number");
        console.log(type(uint256).max / 1e18);
        console.log("uint112 max number");
        console.log(type(uint112).max / 1e18);

        console.log(2 ** 112);
    }
}
