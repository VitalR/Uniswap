// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

library Tick {
    struct Info {
        bool initialized;
        uint128 liquidity;
    }

    function update(mapping(int24 => Tick.Info) storage self, int24 tick, uint128 liquidityDelta)
        internal
        returns (bool flipped)
    {
        Tick.Info storage tickInfo = self[tick];
        uint128 liquidityBefore = tickInfo.liquidity;
        uint128 liquidityAfter = liquidityBefore + liquidityDelta;

        // flipped = (liquidityBefore == 0 && liquidityAfter > 0) //liquidity activated
        //        || (liquidityBefore > 0 && liquidityAfter == 0) //liquidity de-activated
        flipped = (liquidityAfter == 0) != (liquidityBefore == 0);

        if (liquidityBefore == 0) {
            tickInfo.initialized = true;
        }

        tickInfo.liquidity = liquidityAfter;
    }
}
