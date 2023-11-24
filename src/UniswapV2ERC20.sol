// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {ERC20} from "@solady/src/tokens/ERC20.sol";

contract UniswapV2ERC20 is ERC20 {
    /// @dev Returns the name of the token.
    function name() public view virtual override returns (string memory) {
        return "Uniswap V2";
    }

    /// @dev Returns the symbol of the token.
    function symbol() public view virtual override returns (string memory) {
        return "UNI-V2";
    }
}
