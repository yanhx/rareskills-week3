// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console, stdError} from "forge-std/Test.sol";
import {UniswapV2Factory} from "../../src/UniswapV2Factory.sol";
import {UniswapV2Pair} from "../../src/UniswapV2Pair.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {ERC20Mock} from "lib/solady/ext/woke/ERC20Mock.sol";

contract FlashBorrowerTest is Test {
    address public _feeToSetter = address(0x30);
    address public pairAddress;
    address lenderAddress;

    FlashBorrower flashBorrower;
    ERC20Mock tokenA;
    ERC20Mock tokenB;
    ERC20Mock public token0;
    ERC20Mock public token1;

    UniswapV2Pair public uniswapV2Pair;
    UniswapV2Factory uniswapV2Factory;

    uint256 public constant INIT_TOKEN_AMT = 1 ether;

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

        lenderAddress = address(uniswapV2Pair);
        console.log("lenderAddress", lenderAddress);

        // token0: 1 * 10 ** token0.decimals();
        // token0: 4 * 10 ** token1.decimals();

        // 1000*1000 = 1*1000,000,  the max token can borrow?

        // create FlashBorrower
        flashBorrower = new FlashBorrower(IERC3156FlashLender(lenderAddress));

        // set which token can be borrowed
        console.log("the valid borrowd token0:", address(token0));
        console.log("the valid borrowd token1:", address(token1));

        token0.transfer(lenderAddress, INIT_TOKEN_AMT / 10);
        token1.transfer(lenderAddress, INIT_TOKEN_AMT / 10);
        UniswapV2Pair(lenderAddress).mint(address(this));
    }

    /**
     * Fee considerations:
     *     when the borrower do the flashloan,should add the fee returned, this is difference from the uniswap_v2 desgin, which decrease the borrow while lending
     *
     *     just for simple, ignore the the consistant between flashloan's fee and swap's fee
     */
    function test_FlashBorrow() public {
        console.log("the valid balance:");
        console.log("token0 balance:", token0.balanceOf(lenderAddress));
        console.log("token1 balance:", token1.balanceOf(lenderAddress));
        // borrow lenderToken0

        uint256 borrowAmount = 0.05 ether;
        //  plus fees:
        uint256 fee = IERC3156FlashLender(lenderAddress).flashFee(address(token0), borrowAmount);

        token0.transfer(address(flashBorrower), fee);

        flashBorrower.flashBorrow(address(token0), borrowAmount);
        // after borrow， check the balance
        assertEq(token0.balanceOf(address(flashBorrower)), 0);

        // beyond max borrow
        borrowAmount = 0.2 ether;
        vm.expectRevert(bytes("FlashLender: Exceeded max loan"));
        flashBorrower.flashBorrow(address(token0), borrowAmount);
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

contract FlashBorrower is IERC3156FlashBorrower {
    enum Action {ARBITRAGE_TRADING}

    IERC3156FlashLender lender;

    uint256 beforeBorrowBalance;

    constructor(IERC3156FlashLender lender_) {
        lender = lender_;
    }

    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data)
        external
        override
        returns (bytes32)
    {
        require(msg.sender == address(lender), "FlashBorrower: Untrusted lender");
        require(initiator == address(this), "FlashBorrower: Untrusted loan initiator");
        console.log("received amount:", ERC20Mock(token).balanceOf(address(this)) - beforeBorrowBalance);
        (Action action) = abi.decode(data, (Action));
        if (action == Action.ARBITRAGE_TRADING) {
            console.log("Can do ARBITRAGE_TRADING while in this stage,received token amount,", amount);
        }
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    /// @dev Initiate a flash loan
    function flashBorrow(address token, uint256 amount) public {
        bytes memory data = abi.encode(Action.ARBITRAGE_TRADING);
        uint256 _allowance = ERC20Mock(token).allowance(address(this), address(lender));
        uint256 _fee = lender.flashFee(token, amount);
        uint256 _repayment = amount + _fee;
        console.log("_repayment", _repayment);
        ERC20Mock(token).approve(address(lender), _allowance + _repayment);
        console.log("-------------------------start flash borrow-------------------------");
        console.log("amount,fee", amount, _fee);
        beforeBorrowBalance = ERC20Mock(token).balanceOf(address(this));
        lender.flashLoan(this, token, amount, data);
        console.log("-------------------------end flash borrow-------------------------");
    }
}
