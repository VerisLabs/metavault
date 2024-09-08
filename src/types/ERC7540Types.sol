/// SPDX-License-Identifer: MIT
pragma solidity 0.8.21;

import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";

type ERC7540_Request is uint256;

struct ERC7540_FilledRequest {
    uint256 assets;
    uint256 shares;
}

library ERC7540Lib {
    function convertToSharesUp(ERC7540_FilledRequest memory self, uint256 assets) internal pure returns (uint256) {
        return FixedPointMathLib.fullMulDivUp(self.shares, assets, self.assets);
    }

    function convertToShares(ERC7540_FilledRequest memory self, uint256 assets) internal pure returns (uint256) {
        return FixedPointMathLib.fullMulDiv(self.shares, assets, self.assets);
    }

    function convertToAssets(ERC7540_FilledRequest memory self, uint256 shares) internal pure returns (uint256) {
        return FixedPointMathLib.fullMulDivUp(self.assets, shares, self.shares);
    }

    function convertToAssetsUp(ERC7540_FilledRequest memory self, uint256 shares) internal pure returns (uint256) {
        return FixedPointMathLib.fullMulDivUp(self.assets, shares, self.shares);
    }

    function add(ERC7540_Request self, uint256 x) internal pure returns (ERC7540_Request) {
        return ERC7540_Request.wrap(ERC7540_Request.unwrap(self) + x);
    }

    function sub(ERC7540_Request self, uint256 x) internal pure returns (ERC7540_Request) {
        return ERC7540_Request.wrap(ERC7540_Request.unwrap(self) - x);
    }

    function unwrap(ERC7540_Request self) internal pure returns (uint256) {
        return ERC7540_Request.unwrap(self);
    }
}
