1. Relative Stability : Anchored or Pegged -> 1$
   1. Chainlink Price Feed
   2. Set a function to exchange ETH & BTC -> $$$

2. Stability Mechanism (Minting) : ALgorithmic (Decentralized)
   1. People can only mint the stablecoin with enough collateral

3. Collateral: exogenous (Crypto)
   1. weth
   2. wbtc

## How does the protocol works?

1. Users deposit ETH or BTC as collateral and mint stablecoins
2. The protocol uses Chainlink price feeds to determine the value of the collateral
3. The protocol has a liquidation mechanism to ensure that the value of the collateral is always greater than the value of the stablecoins minted


    /**
     * @dev  Threshold sets to lets say 150%
     *          you have minted $50 worth of DSC
     *          you have $100 worth of collateral (means you are 200% collateralized)
     *          you must have at least 75$ worth of collateral not to be liquidated
     *          you can redeem $25 worth of collateral
     */


### threshold
```bash

  1e18 = ((collateralValueInUsd * 50) / 100) * 1e18 / totalDscMinted
  (collateralValueInUsd * 0.5) * 1e18 / totalDscMinted = 1e18
  collateralValueInUsd * 0.5 = totalDscMinted
  collateralValueInUsd = totalDscMinted * 2

```
  This means the collateral value must be 2x (200%) the DSC debt to achieve a health factor of 1e18, confirming that a 50% threshold indeed implies a 200% over-collateralization requirement.

  ## Redeem Collateral
  1. A user with sufficient collateral and a healthy position (health factor > 1e18 after redeeming) can redeem their collateral.
   

## Liquidation
   1. Liquidate a user with a broken health factor (health factor < 1e18)

## Handler Contract:

 * The Handler contract defines functions that Foundry can call during invariant testing: depositCollateral, mintDSC, redeemCollateral, and burnDSC.


 * It ensures realistic behavior:
  Users must deposit collateral before minting DSC.
  Amounts are bounded to reasonable values using bound.
  Functions like redeemCollateral and burnDSC check if the user has sufficient collateral/DSC before proceeding.

 * It also manages a list of users to simulate multiple actors.
 
