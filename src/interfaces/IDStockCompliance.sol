// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IDStockCompliance {
  // action: 0=Transfer, 1=Wrap, 2=Unwrap
  function isTransferAllowed(
    address token,
    address from,
    address to,
    uint256 amount,
    uint8 action
  ) external view returns (bool);
}
