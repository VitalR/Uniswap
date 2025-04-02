// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

/// @title Oracle Library
/// @notice Provides functions for managing and retrieving time-weighted average prices and tick data.
/// @dev This library is used to record and query historical tick observations for Uniswap V3-style pools.
library Oracle {
    // Define a custom error for the "OLD" condition
    error OldObservation();
    
    /// @notice Represents an observation in the oracle.
    /// @param timestamp The timestamp of the observation.
    /// @param tickCumulative The cumulative sum of the ticks up to the timestamp.
    /// @param initialized Indicates whether the observation has been initialized.
    struct Observation {
        uint32 timestamp;
        int56 tickCumulative;
        bool initialized;
    }

    /// @notice Initializes the first observation in the oracle.
    /// @param self The storage array of observations.
    /// @param time The timestamp of the first observation.
    /// @return cardinality The number of initialized observations.
    /// @return cardinalityNext The next cardinality target.
    function initialize(Observation[65_535] storage self, uint32 time)
        internal
        returns (uint16 cardinality, uint16 cardinalityNext)
    {
        self[0] = Observation({ timestamp: time, tickCumulative: 0, initialized: true });

        cardinality = 1;
        cardinalityNext = 1;
    }

    /// @notice Writes a new observation to the oracle.
    /// @param self The storage array of observations.
    /// @param index The index of the last written observation.
    /// @param timestamp The timestamp of the new observation.
    /// @param tick The tick value to record.
    /// @param cardinality The current number of initialized observations.
    /// @param cardinalityNext The target number of observations.
    /// @return indexUpdated The updated index of the last written observation.
    /// @return cardinalityUpdated The updated cardinality.
    function write(
        Observation[65_535] storage self,
        uint16 index,
        uint32 timestamp,
        int24 tick,
        uint16 cardinality,
        uint16 cardinalityNext
    ) internal returns (uint16 indexUpdated, uint16 cardinalityUpdated) {
        Observation memory last = self[index];

        if (last.timestamp == timestamp) return (index, cardinality);

        if (cardinalityNext > cardinality && index == (cardinality - 1)) {
            cardinalityUpdated = cardinalityNext;
        } else {
            cardinalityUpdated = cardinality;
        }

        indexUpdated = (index + 1) % cardinalityUpdated;
        self[indexUpdated] = transform(last, timestamp, tick);
    }

    /// @notice Expands the cardinality of the observation array.
    /// @param self The storage array of observations.
    /// @param current The current cardinality.
    /// @param next The target cardinality.
    /// @return The updated cardinality.
    function grow(Observation[65_535] storage self, uint16 current, uint16 next) internal returns (uint16) {
        if (next <= current) return current;

        for (uint16 i = current; i < next; i++) {
            self[i].timestamp = 1;
        }

        return next;
    }

    /// @notice Transforms the last observation to create a new one.
    /// @param last The last observation.
    /// @param timestamp The timestamp of the new observation.
    /// @param tick The tick value to include in the new observation.
    /// @return The new observation.
    function transform(Observation memory last, uint32 timestamp, int24 tick)
        internal
        pure
        returns (Observation memory)
    {
        uint56 delta = timestamp - last.timestamp;

        return Observation({
            timestamp: timestamp,
            tickCumulative: last.tickCumulative + int56(tick) * int56(delta),
            initialized: true
        });
    }

    /// @notice Determines if `a` is less than or equal to `b` with time overflow consideration.
    /// @param time The current time.
    /// @param a The first timestamp.
    /// @param b The second timestamp.
    /// @return True if `a` <= `b`, considering time overflow.
    function lte(uint32 time, uint32 a, uint32 b) private pure returns (bool) {
        // Both timestamps are in the past (relative to time)
        if (a <= time && b <= time) return a <= b;

        // Handle cases where timestamps wrap around uint32
        uint256 aAdjusted = a > time ? a : a + 2 ** 32;
        uint256 bAdjusted = b > time ? b : b + 2 ** 32;

        return aAdjusted <= bAdjusted;
    }

    /// @notice Performs a binary search to find the surrounding observations for a target timestamp.
    /// @param self The storage array of observations.
    /// @param time The current time.
    /// @param target The target timestamp.
    /// @param index The index of the most recent observation.
    /// @param cardinality The number of initialized observations.
    /// @return beforeOrAt The observation at or before the target.
    /// @return atOrAfter The observation at or after the target.
    function binarySearch(
        Observation[65_535] storage self,
        uint32 time,
        uint32 target,
        uint16 index,
        uint16 cardinality
    ) private view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        uint256 l = (index + 1) % cardinality; // Oldest observation
        uint256 r = l + cardinality - 1; // Newest observation
        uint256 i;

        while (true) {
            i = (l + r) / 2;

            beforeOrAt = self[i % cardinality];

            if (!beforeOrAt.initialized) {
                l = i + 1;
                continue;
            }

            atOrAfter = self[(i + 1) % cardinality];

            bool targetAtOrAfter = lte(time, beforeOrAt.timestamp, target);

            if (targetAtOrAfter && lte(time, target, atOrAfter.timestamp)) {
                break;
            }

            if (!targetAtOrAfter) r = i - 1;
            else l = i + 1;
        }
    }

    /// @notice Retrieves the observations surrounding a target timestamp.
    /// @dev Determines the observations immediately before or at the target timestamp and at or after the target
    /// timestamp. If the target timestamp matches an existing observation, it returns that observation directly.
    /// Otherwise, it interpolates or searches for the surrounding observations.
    /// @param self The storage array of observations.
    /// @param time The current time, used for overflow comparison.
    /// @param target The target timestamp for which surrounding observations are needed.
    /// @param tick The current tick value, used for interpolation.
    /// @param index The index of the most recent observation.
    /// @param cardinality The total number of initialized observations.
    /// @return beforeOrAt The observation at or before the target timestamp.
    /// @return atOrAfter The observation at or after the target timestamp.
    function getSurroundingObservations(
        Observation[65_535] storage self,
        uint32 time,
        uint32 target,
        int24 tick,
        uint16 index,
        uint16 cardinality
    ) private view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        beforeOrAt = self[index];

        // If the target is at or after the last observation
        if (lte(time, beforeOrAt.timestamp, target)) {
            // If the target matches the last observation, return it directly
            if (beforeOrAt.timestamp == target) {
                return (beforeOrAt, atOrAfter);
            } else {
                // Interpolate to create an observation at the target
                return (beforeOrAt, transform(beforeOrAt, target, tick));
            }
        }

        // If the target is before the last observation, find the oldest observation
        beforeOrAt = self[(index + 1) % cardinality];
        if (!beforeOrAt.initialized) beforeOrAt = self[0];

        // Ensure the target is within a valid range (not too old)
        // require(lte(time, beforeOrAt.timestamp, target), "OLD");
        if (!lte(time, beforeOrAt.timestamp, target)) {
            revert OldObservation();
        }

        // Otherwise, perform binary search to find surrounding observations
        return binarySearch(self, time, target, index, cardinality);
    }

    /// @notice Observes a single cumulative tick at a specified time offset.
    /// @param self The storage array of observations.
    /// @param time The current time.
    /// @param secondsAgo The time offset from the current time.
    /// @param tick The current tick.
    /// @param index The index of the most recent observation.
    /// @param cardinality The number of initialized observations.
    /// @return tickCumulative The cumulative tick at the specified time offset.
    function observeSingle(
        Observation[65_535] storage self,
        uint32 time,
        uint32 secondsAgo,
        int24 tick,
        uint16 index,
        uint16 cardinality
    ) internal view returns (int56 tickCumulative) {
        if (secondsAgo == 0) {
            Observation memory last = self[index];
            if (last.timestamp != time) last = transform(last, time, tick);
            return last.tickCumulative;
        }

        uint32 target = time - secondsAgo;
        
        (Observation memory beforeOrAt, Observation memory atOrAfter) =
            getSurroundingObservations(self, time, target, tick, index, cardinality);

        if (target == beforeOrAt.timestamp) {
            return beforeOrAt.tickCumulative;
        } else if (target == atOrAfter.timestamp) {
            return atOrAfter.tickCumulative;
        } else {
            uint56 observationTimeDelta = atOrAfter.timestamp - beforeOrAt.timestamp;
            uint56 targetDelta = target - beforeOrAt.timestamp;
            return beforeOrAt.tickCumulative
                + ((atOrAfter.tickCumulative - beforeOrAt.tickCumulative) / int56(observationTimeDelta))
                    * int56(targetDelta);
        }
    }

    /// @notice Observes multiple cumulative ticks at specified time offsets.
    /// @param self The storage array of observations.
    /// @param time The current time.
    /// @param secondsAgos An array of time offsets from the current time.
    /// @param tick The current tick.
    /// @param index The index of the most recent observation.
    /// @param cardinality The number of initialized observations.
    /// @return tickCumulatives An array of cumulative ticks at the specified time offsets.
    function observe(
        Observation[65_535] storage self,
        uint32 time,
        uint32[] memory secondsAgos,
        int24 tick,
        uint16 index,
        uint16 cardinality
    ) internal view returns (int56[] memory tickCumulatives) {
        tickCumulatives = new int56[](secondsAgos.length);

        for (uint256 i = 0; i < secondsAgos.length; i++) {
            tickCumulatives[i] = observeSingle(self, time, secondsAgos[i], tick, index, cardinality);
        }
    }
}
