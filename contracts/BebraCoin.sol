//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "hardhat/console.sol";

abstract contract Bebra is IERC20 {
    uint256 internal constant INFINITE_ALLOWANCE = ~uint256(0);
    mapping(address => uint256) private shares;
    mapping(address => mapping(address => uint256)) private allowances;
    uint internal TOTAL_SHARES_POSITION;
    address internal constant INITIAL_TOKEN_HOLDER =
        0x0000000000000000000000000000000000000000;
    event TransferShares(
        address indexed from,
        address indexed to,
        uint256 sharesValue
    );
    event SharesBurnt(
        address indexed account,
        uint256 preRebaseTokenAmount,
        uint256 postRebaseTokenAmount,
        uint256 sharesAmount
    );

    // constructor() {
    //     _mintInitialShares(2 ** 256 - 1);
    // }

    function name() external pure returns (string memory) {
        return "BebraCoin 228";
    }

    function symbol() external pure returns (string memory) {
        return "BBR";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function totalSupply() external view returns (uint256) {
        return _getTotalPooledAmount();
    }

    function balanceOf(address _account) external view returns (uint256) {
        return getPooledAmountByShares(_sharesOf(_account));
    }

    function transfer(
        address _recipient,
        uint256 _amount
    ) external returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function allowance(
        address _owner,
        address _spender
    ) external view returns (uint256) {
        return allowances[_owner][_spender];
    }

    function approve(
        address _spender,
        uint256 _amount
    ) external returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external returns (bool) {
        _spendAllowance(_sender, msg.sender, _amount);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function increaseAllowance(
        address _spender,
        uint256 _addedValue
    ) external returns (bool) {
        _approve(
            msg.sender,
            _spender,
            allowances[msg.sender][_spender] + (_addedValue)
        );
        return true;
    }

    function decreaseAllowance(
        address _spender,
        uint256 _subtractedValue
    ) external returns (bool) {
        uint256 currentAllowance = allowances[msg.sender][_spender];
        require(currentAllowance >= _subtractedValue, "ALLOWANCE_BELOW_ZERO");
        _approve(msg.sender, _spender, currentAllowance - _subtractedValue);
        return true;
    }

    function getTotalShares() external view returns (uint256) {
        return _getTotalShares();
    }

    function sharesOf(address _account) external view returns (uint256) {
        return _sharesOf(_account);
    }

    /**
     * @return the amount of shares that corresponds to `_ethAmount` protocol-controlled Ether.
     */
    function getSharesByPooledAmount(
        uint256 _Amount
    ) public view returns (uint256) {
        uint pooledAmount = _getTotalPooledAmount();
        if (pooledAmount > 0) {
            return (_Amount * (_getTotalShares())) / (pooledAmount);
        } else {
            return 0;
        }
    }

    /**
     * @return the amount of Ether that corresponds to `_sharesAmount` token shares.
     */
    function getPooledAmountByShares(
        uint256 _sharesAmount
    ) public view returns (uint256) {
        uint totalShares = _getTotalShares();
        if (totalShares > 0) {
            return (_sharesAmount * (_getTotalPooledAmount())) / (totalShares);
        } else {
            return 0;
        }
    }

    /**
     * @notice Moves `_sharesAmount` token shares from the caller's account to the `_recipient` account.
     *
     * @return amount of transferred tokens.
     * Emits a `TransferShares` event.
     * Emits a `Transfer` event.
     *
     * Requirements:
     *
     * - `_recipient` cannot be the zero address.
     * - the caller must have at least `_sharesAmount` shares.
     * - the contract must not be paused.
     *
     * @dev The `_sharesAmount` argument is the amount of shares, not tokens.
     */
    function transferShares(
        address _recipient,
        uint256 _sharesAmount
    ) external returns (uint256) {
        _transferShares(msg.sender, _recipient, _sharesAmount);
        uint256 tokensAmount = getPooledAmountByShares(_sharesAmount);
        _emitTransferEvents(
            msg.sender,
            _recipient,
            tokensAmount,
            _sharesAmount
        );
        return tokensAmount;
    }

    /**
     * @notice Moves `_sharesAmount` token shares from the `_sender` account to the `_recipient` account.
     *
     * @return amount of transferred tokens.
     * Emits a `TransferShares` event.
     * Emits a `Transfer` event.
     *
     * Requirements:
     *
     * - `_sender` and `_recipient` cannot be the zero addresses.
     * - `_sender` must have at least `_sharesAmount` shares.
     * - the caller must have allowance for `_sender`'s tokens of at least `getPooledEthByShares(_sharesAmount)`.
     * - the contract must not be paused.
     *
     * @dev The `_sharesAmount` argument is the amount of shares, not tokens.
     */
    function transferSharesFrom(
        address _sender,
        address _recipient,
        uint256 _sharesAmount
    ) external returns (uint256) {
        uint256 tokensAmount = getPooledAmountByShares(_sharesAmount);
        _spendAllowance(_sender, msg.sender, tokensAmount);
        _transferShares(_sender, _recipient, _sharesAmount);
        _emitTransferEvents(_sender, _recipient, tokensAmount, _sharesAmount);
        return tokensAmount;
    }

    /**
     * @return the total amount (in wei) of Ether controlled by the protocol.
     * @dev This is used for calculating tokens from shares and vice versa.
     * @dev This function is required to be implemented in a derived contract.
     */
    function _getTotalPooledAmount() internal view virtual returns (uint256) {
        // return strategyManager.getTotalPooledAmount();
    }

    /**
     * @notice Moves `_amount` tokens from `_sender` to `_recipient`.
     * Emits a `Transfer` event.
     * Emits a `TransferShares` event.
     */
    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) internal {
        uint256 _sharesToTransfer = getSharesByPooledAmount(_amount);
        _transferShares(_sender, _recipient, _sharesToTransfer);
        _emitTransferEvents(_sender, _recipient, _amount, _sharesToTransfer);
    }

    /**
     * @notice Sets `_amount` as the allowance of `_spender` over the `_owner` s tokens.
     *
     * Emits an `Approval` event.
     *
     * NB: the method can be invoked even if the protocol paused.
     *
     * Requirements:
     *
     * - `_owner` cannot be the zero address.
     * - `_spender` cannot be the zero address.
     */
    function _approve(
        address _owner,
        address _spender,
        uint256 _amount
    ) internal {
        require(_owner != address(0), "APPROVE_FROM_ZERO_ADDR");
        require(_spender != address(0), "APPROVE_TO_ZERO_ADDR");

        allowances[_owner][_spender] = _amount;
        emit Approval(_owner, _spender, _amount);
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
     *
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
    function _spendAllowance(
        address _owner,
        address _spender,
        uint256 _amount
    ) internal {
        uint256 currentAllowance = allowances[_owner][_spender];
        if (currentAllowance != INFINITE_ALLOWANCE) {
            require(currentAllowance >= _amount, "ALLOWANCE_EXCEEDED");
            _approve(_owner, _spender, currentAllowance - _amount);
        }
    }

    /**
     * @return the total amount of shares in existence.
     */
    function _getTotalShares() internal view returns (uint256) {
        return TOTAL_SHARES_POSITION;
    }

    /**
     * @return the amount of shares owned by `_account`.
     */
    function _sharesOf(address _account) internal view returns (uint256) {
        return shares[_account];
    }

    /**
     * @notice Moves `_sharesAmount` shares from `_sender` to `_recipient`.
     *
     * Requirements:
     *
     * - `_sender` cannot be the zero address.
     * - `_recipient` cannot be the zero address or the `stETH` token contract itself
     * - `_sender` must hold at least `_sharesAmount` shares.
     * - the contract must not be paused.
     */
    function _transferShares(
        address _sender,
        address _recipient,
        uint256 _sharesAmount
    ) internal {
        require(_sender != address(0), "TRANSFER_FROM_ZERO_ADDR");
        require(_recipient != address(0), "TRANSFER_TO_ZERO_ADDR");
        require(_recipient != address(this), "TRANSFER_TO_this_CONTRACT");

        uint256 currentSenderShares = shares[_sender];
        require(_sharesAmount <= currentSenderShares, "BALANCE_EXCEEDED");

        shares[_sender] = currentSenderShares - (_sharesAmount);
        shares[_recipient] = shares[_recipient] + (_sharesAmount);
    }

    /**
     * @notice Creates `_sharesAmount` shares and assigns them to `_recipient`, increasing the total amount of shares.
     * @dev This doesn't increase the token total supply.
     *
     * NB: The method doesn't check protocol pause relying on the external enforcement.
     *
     * Requirements:
     *
     * - `_recipient` cannot be the zero address.
     * - the contract must not be paused.
     */
    function _mintShares(
        address _recipient,
        uint256 _sharesAmount
    ) internal returns (uint256 newTotalShares) {
        require(_recipient != address(0), "MINT_TO_ZERO_ADDR");

        newTotalShares = _getTotalShares() + (_sharesAmount);
        TOTAL_SHARES_POSITION = newTotalShares;

        shares[_recipient] = shares[_recipient] + _sharesAmount;

        // Notice: we're not emitting a Transfer event from the zero address here since shares mint
        // works by taking the amount of tokens corresponding to the minted shares from all other
        // token holders, proportionally to their share. The total supply of the token doesn't change
        // as the result. This is equivalent to performing a send from each other token holder's
        // address to `address`, but we cannot reflect this as it would require sending an unbounded
        // number of events.
    }

    /**
     * @notice Destroys `_sharesAmount` shares from `_account`'s holdings, decreasing the total amount of shares.
     * @dev This doesn't decrease the token total supply.
     *
     * Requirements:
     *
     * - `_account` cannot be the zero address.
     * - `_account` must hold at least `_sharesAmount` shares.
     * - the contract must not be paused.
     */
    function _burnShares(
        address _account,
        uint256 _sharesAmount
    ) internal returns (uint256 newTotalShares) {
        require(_account != address(0), "BURN_FROM_ZERO_ADDR");

        uint256 accountShares = shares[_account];
        require(_sharesAmount <= accountShares, "BALANCE_EXCEEDED");

        uint256 preRebaseTokenAmount = getPooledAmountByShares(_sharesAmount);

        newTotalShares = _getTotalShares() - (_sharesAmount);
        TOTAL_SHARES_POSITION = newTotalShares;

        shares[_account] = accountShares - (_sharesAmount);

        uint256 postRebaseTokenAmount = getPooledAmountByShares(_sharesAmount);

        emit SharesBurnt(
            _account,
            preRebaseTokenAmount,
            postRebaseTokenAmount,
            _sharesAmount
        );

        // Notice: we're not emitting a Transfer event to the zero address here since shares burn
        // works by redistributing the amount of tokens corresponding to the burned shares between
        // all other token holders. The total supply of the token doesn't change as the result.
        // This is equivalent to performing a send from `address` to each other token holder address,
        // but we cannot reflect this as it would require sending an unbounded number of events.

        // We're emitting `SharesBurnt` event to provide an explicit rebase log record nonetheless.
    }

    /**
     * @dev Emits {Transfer} and {TransferShares} events
     */
    function _emitTransferEvents(
        address _from,
        address _to,
        uint _tokenAmount,
        uint256 _sharesAmount
    ) internal {
        emit Transfer(_from, _to, _tokenAmount);
        emit TransferShares(_from, _to, _sharesAmount);
    }

    /**
     * @dev Emits {Transfer} and {TransferShares} events where `from` is 0 address. Indicates mint events.
     */
    function _emitTransferAfterMintingShares(
        address _to,
        uint256 _sharesAmount
    ) internal {
        _emitTransferEvents(
            address(0),
            _to,
            getPooledAmountByShares(_sharesAmount),
            _sharesAmount
        );
    }

    /**
     * @dev Mints shares to INITIAL_TOKEN_HOLDER
     */
    function _mintInitialShares(uint256 _sharesAmount) internal {
        _mintShares(INITIAL_TOKEN_HOLDER, _sharesAmount);
        _emitTransferAfterMintingShares(INITIAL_TOKEN_HOLDER, _sharesAmount);
    }
}
