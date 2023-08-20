// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// libraries
import {ERC4626, ERC20, Math, SafeERC20} from "./libs/ModifiedERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Pool is ERC4626 {
    using Math for uint256;

    /**************************************************************************/
    /* Constructor */
    /**************************************************************************/
    // TODO: add name/symbol logic to factory
    constructor(
        address asset_,
        string memory name_,
        string memory symbol_,
        address admin_
    ) ERC4626(IERC20(asset_)) ERC20(name_, symbol_) {}

    /**************************************************************************/
    /* Overridden Vault API */
    /**************************************************************************/

    /** @dev Was created in order to deposit native token into the pool when the asset address is address(0).
     */
    function depositNativeToken() external payable {
        require(address(_asset) == address(0), "Pool: asset is not ETH");
        deposit(msg.value, msg.sender);
    }

    /** @dev See {IERC4626-maxWithdraw}.
     * Was modified to return the was is widrawable depending on the balance held by the pool.
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 expectedBalance = _convertToAssets(balanceOf(owner), Math.Rounding.Down);
        if (expectedBalance >= totalAssets()) {
            return totalAssets();
        } else {
            return expectedBalance;
        }
    }

    /** @dev See {IERC4626-totalAssets}.
     * Was modified to support ETH as an asset, and return the balance of the asset held by the pool.
     * @return The total value of the assets held by the pool.
     */
    function totalAssets() public view override returns (uint256) {
        if (address(_asset) == address(0)) {
            return address(this).balance;
        } else {
            return _asset.balanceOf(address(this));
        }
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (address(_asset) != address(0)) {
            require(msg.value == 0, "Pool: ETH deposit amount mismatch");
            // If _asset is ERC777, `transferFrom` can trigger a reentrancy BEFORE the transfer happens through the
            // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
            // calls the vault, which is assumed not malicious.
            //
            // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
            // assets are transferred and before the shares are minted, which is a valid state.
            // slither-disable-next-line reentrancy-no-eth
            SafeERC20.safeTransferFrom(_asset, caller, address(this), assets);
        }

        _mint(receiver, shares);
        emit Deposit(caller, receiver, assets, shares);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        // If _asset is ERC777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transferred, which is a valid state.
        _burn(owner, shares);
        if (address(_asset) == address(0)) {
            require(receiver == owner, "Pool: receiver is not owner");
            // slither-disable-next-line reentrancy-no-eth
            payable(receiver).transfer(assets);
        } else {
            if (caller != owner) {
                _spendAllowance(owner, caller, shares);
            }
            // slither-disable-next-line reentrancy-no-eth
            SafeERC20.safeTransfer(_asset, receiver, assets);
        }
        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /**************************************************************************/
    /* Admin API */
    /**************************************************************************/
}
