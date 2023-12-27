//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Icomptroller.sol";
import "./IsoToken.sol";
import "./IveloRouter.sol";
import "./Iunitroller.sol";
import "./IOracle.sol";
import "./IPool.sol";
import "./IPoolFactory.sol";
import "./IGauge.sol";
import "./IPositionManager.sol";

import "hardhat/console.sol";

contract DNSPositionManager is Ownable, IPositionManager {
    IERC20 _initToken;
    IPool _poolToken;
    IsoToken _soToken1;
    IsoToken _soToken2;
    IOracle oracle;
    IERC20 _token1;
    IERC20 _token2;
    struct Addresses {
        address SONNEaddress;
        address comptroller;
        address veloRouter;
        address unitroller;
        address poolTokenAddress;
        address soToken1Address;
        address soToken2Address;
        address oracleAddress;
        address InitTokenAddress;
        address veloFactory;
        address poolTokenGauge;
    }
    Addresses public addresses;
    struct Parameters {
        uint collateralFactor;
        uint _healthFactor;
        uint _hfUp;
        uint _hfDown;
    }
    Parameters public params;
    struct AccountSnapshot {
        uint LPToken1Amount;
        uint LPToken2Amount;
        uint supplyBalance;
        uint borrowBalance;
        uint borrowBalanceUSD;
        uint supplyBalanceUSD;
        uint LPBalanceUSD;
        uint healthFactorCurrent;
        uint hedgingPercentageCurrent;
        uint totalAmount;
    }
    struct PosCalc {
        uint LPAmountUSD;
        uint borrowAmountUSD;
        uint supplyAmountUSD;
        uint borrowAmount;
        uint supplyAmount;
        uint token1Price;
        uint token2Price;
    }

    constructor(
        Addresses memory addressesStruct,
        Parameters memory paramsStruct
    ) Ownable(msg.sender) {
        addresses = addressesStruct;
        params = paramsStruct;
        require(
            params._hfUp > params._healthFactor &&
                params._healthFactor > params._hfDown &&
                params._hfDown > 1e18,
            "wrong hf parameters"
        );
        _soToken1 = IsoToken(addresses.soToken1Address);
        _soToken2 = IsoToken(addresses.soToken2Address);
        oracle = IOracle(addresses.oracleAddress);
        _initToken = IERC20(addresses.InitTokenAddress);
        _poolToken = IPool(addresses.poolTokenAddress);
        _token1 = IERC20(_poolToken.token0());
        _token2 = IERC20(_poolToken.token1());
        listSoToken();
    }

    function setStrategyParams(
        Parameters calldata paramsStruct
    ) external onlyOwner {
        params = paramsStruct;
        require(
            params._hfUp > params._healthFactor &&
                params._healthFactor > params._hfDown &&
                params._hfDown > 1e18,
            "wrong hf parameters"
        );
    }

    function listSoToken() internal {
        IERC20(address(_token2)).approve(address(_soToken1), 2 ** 256 - 1);
        IERC20(address(_token1)).approve(address(_soToken2), 2 ** 256 - 1);
        IERC20(addresses.poolTokenAddress).approve(
            addresses.poolTokenGauge,
            2 ** 256 - 1
        );
        IERC20(addresses.poolTokenAddress).approve(
            addresses.veloRouter,
            2 ** 256 - 1
        );
        address[] memory cTokens = new address[](1);
        cTokens[0] = addresses.soToken1Address;
        Icomptroller(addresses.comptroller).enterMarkets(cTokens);
    }

    function openPosition(uint initialAmount) external {
        require(
            _initToken.balanceOf(msg.sender) >= initialAmount,
            "your balance not enough"
        );
        console.log("opening position with balance", initialAmount);
        SafeERC20.safeTransferFrom(
            _initToken,
            msg.sender,
            address(this),
            initialAmount
        );
        _getIntoPosition(initialAmount, false);
    }

    function calcPosition(
        uint initialAmount,
        bool isRebalance
    ) public view returns (PosCalc memory) {
        PosCalc memory poscalc;
        uint numerator = 1e6;
        uint oracleMantissa = 1e30;
        (poscalc.token1Price, poscalc.token2Price) = _getOraclePrices(
            _soToken1,
            _soToken2
        );

        AccountSnapshot memory snapshot = getAccountSnapshot();

        uint initialAmountUSD = (initialAmount * poscalc.token1Price) /
            oracleMantissa;
        uint fullAmountUSD;
        if (isRebalance == true) {
            fullAmountUSD = initialAmountUSD + snapshot.totalAmount;
        } else {
            fullAmountUSD = initialAmountUSD;
        }
        poscalc.LPAmountUSD =
            (numerator * (2 * fullAmountUSD)) /
            (numerator +
                ((numerator * params._healthFactor) / params.collateralFactor));
        poscalc.borrowAmountUSD = (poscalc.LPAmountUSD / 2);
        poscalc.supplyAmountUSD = (
            ((params._healthFactor * poscalc.borrowAmountUSD) /
                params.collateralFactor)
        );
        poscalc.supplyAmount =
            (poscalc.supplyAmountUSD * oracleMantissa) /
            poscalc.token1Price;
        poscalc.borrowAmount =
            (poscalc.borrowAmountUSD * oracleMantissa) /
            poscalc.token2Price;
        return poscalc;
    }

    function _getOraclePrices(
        IsoToken soToken1,
        IsoToken soToken2
    ) internal view returns (uint asset1Price, uint asset2Price) {
        uint price1 = oracle.getUnderlyingPrice(soToken1);
        uint price2 = oracle.getUnderlyingPrice(soToken2);
        return (price1, price2);
    }

    function triggerRebalance() external onlyOwner {
        AccountSnapshot memory accountSnapshot = getAccountSnapshot();
        require(
            accountSnapshot.healthFactorCurrent > params._hfUp ||
                accountSnapshot.healthFactorCurrent < params._hfDown,
            "no need to rebalance"
        );
        _getIntoPosition(uint(0), true);
    }

    function _getIntoPosition(uint initialAmount, bool isRebalance) internal {
        PosCalc memory poscalc = calcPosition(initialAmount, isRebalance);
        AccountSnapshot memory accountSnapshot = getAccountSnapshot();
        int supplyTokenDelta;
        int borrowTokenDelta;
        if (isRebalance == true) {
            supplyTokenDelta =
                int(poscalc.supplyAmount) -
                int(accountSnapshot.supplyBalance);
            borrowTokenDelta =
                int(poscalc.borrowAmount) -
                int(accountSnapshot.borrowBalance);
        } else {
            supplyTokenDelta = int(poscalc.supplyAmount);
            borrowTokenDelta = int(poscalc.borrowAmount);
        }

        if (supplyTokenDelta > 0 && borrowTokenDelta > 0) {
            _soToken1.mint(uint(supplyTokenDelta));
            _soToken2.borrow(uint(borrowTokenDelta));
        }
        if (supplyTokenDelta > 0 && borrowTokenDelta < 0) {
            _removeLiquidity(1e18);
            _soToken1.mint(uint(supplyTokenDelta));
            _checkForAdditionalSwap(accountSnapshot, 1e18);
            _soToken2.repayBorrow(uint(-borrowTokenDelta));
        }
        if (supplyTokenDelta < 0 && borrowTokenDelta < 0) {
            _removeLiquidity(1e18);
            _checkForAdditionalSwap(accountSnapshot, 1e18);
            _soToken2.repayBorrow(uint(-borrowTokenDelta));
            _soToken1.redeemUnderlying(uint(-supplyTokenDelta));
        }
        if (supplyTokenDelta < 0 && borrowTokenDelta > 0) {
            _soToken1.redeemUnderlying(uint(-supplyTokenDelta));
            _soToken2.borrow(uint(borrowTokenDelta));
        }

        _swapAndAdd();
        IGauge(addresses.poolTokenGauge).deposit(
            _poolToken.balanceOf(address(this))
        );
    }

    function _quoteSwap()
        internal
        view
        returns (uint amountIn, address tokenIn, address tokenOut)
    {
        uint token1WalletAmount = _token1.balanceOf(address(this));
        uint token2WalletAmount = _token2.balanceOf(address(this));
        (, , uint reserves1, uint reserves2) = _getReserves(
            address(_poolToken)
        );
        uint tokensLiquidity1 = (token2WalletAmount * reserves1) /
            reserves2 +
            token1WalletAmount;
        if (token1WalletAmount > tokensLiquidity1 / 2) {
            return (
                token1WalletAmount - tokensLiquidity1 / 2,
                address(_token1),
                address(_token2)
            );
        } else {
            uint tokensLiquidity2 = (token1WalletAmount * reserves2) /
                reserves1 +
                token2WalletAmount;
            return (
                token2WalletAmount - tokensLiquidity2 / 2,
                address(_token2),
                address(_token1)
            );
        }
    }

    function swapInTargetProportion() internal {
        (uint amountIn, address tokenIn, address tokenOut) = _quoteSwap();
        _swap(amountIn, tokenIn, tokenOut);
    }

    function _swap(uint amountIn, address tokenIn, address tokenOut) internal {
        IERC20(tokenIn).approve(addresses.veloRouter, amountIn);

        IveloRouter.Route[] memory route = new IveloRouter.Route[](1);
        route[0] = IveloRouter.Route({
            from: tokenIn,
            to: tokenOut,
            stable: false,
            factory: addresses.veloFactory
        });
        uint256[] memory amounts = IveloRouter(addresses.veloRouter)
            .getAmountsOut(amountIn, route);
        uint amount = amounts[1];

        require(amount > 0, "bad swap");
        IveloRouter(addresses.veloRouter).swapExactTokensForTokens(
            amountIn,
            amount,
            route,
            address(this),
            block.timestamp + 6
        );
    }

    function calcAmountInFromAmountOut(
        uint amountOut,
        address tokenIn,
        address tokenOut
    ) internal view returns (uint amountIn) {
        (, , uint reserves1, uint reserves2) = _getReserves(
            address(_poolToken)
        );
        address token0 = address(_token1);
        address token1 = address(_token2);
        require(tokenIn == token0 || tokenIn == token1, "wrong tokens input");
        if (tokenIn == token0 && tokenOut == token1) {
            amountIn =
                (105000000 * (reserves1 * amountOut)) /
                (reserves2 * 1e8);
        }
        if (tokenIn == token1 && tokenOut == token0) {
            amountIn =
                (105000000 * (reserves2 * amountOut)) /
                (reserves1 * 1e8);
        }
        return amountIn;
    }

    function _swapAndAdd() internal {
        swapInTargetProportion();
        uint token1WalletAmount = _token1.balanceOf(address(this));
        uint token2WalletAmount = _token2.balanceOf(address(this));
        _token1.approve(addresses.veloRouter, token1WalletAmount);
        _token2.approve(addresses.veloRouter, token2WalletAmount);
        (uint amountA, uint amountB, ) = IveloRouter(addresses.veloRouter)
            .quoteAddLiquidity(
                address(_token1),
                address(_token2),
                false,
                addresses.veloFactory,
                token1WalletAmount,
                token2WalletAmount
            );

        IveloRouter(addresses.veloRouter).addLiquidity(
            address(_token1),
            address(_token2),
            false,
            token1WalletAmount,
            token2WalletAmount,
            amountA,
            amountB,
            address(this),
            block.timestamp + 50
        );
    }

    function _removeLiquidity(uint sharesPercentage) internal {
        uint poolTokenToUnstake = (sharesPercentage *
            IGauge(addresses.poolTokenGauge).balanceOf(address(this))) / 1e18;
        IGauge(addresses.poolTokenGauge).withdraw(poolTokenToUnstake);
        (uint256 amountA, uint256 amountB) = IveloRouter(addresses.veloRouter)
            .quoteRemoveLiquidity(
                address(_token1),
                address(_token2),
                false,
                addresses.veloFactory,
                _poolToken.balanceOf(address(this))
            );
        IveloRouter(addresses.veloRouter).removeLiquidity(
            address(_token1),
            address(_token2),
            false,
            _poolToken.balanceOf(address(this)),
            amountA,
            amountB,
            address(this),
            block.timestamp + 50
        );
    }

    function _checkForAdditionalSwap(
        AccountSnapshot memory accountSnapshot,
        uint sharesPercentage
    ) internal {
        int additionalTokensForRepay = int(
            (accountSnapshot.borrowBalance * sharesPercentage) / 1e18
        ) - int(_token1.balanceOf(address(this)));
        if (additionalTokensForRepay > 0) {
            uint amountToSwap = calcAmountInFromAmountOut(
                uint(additionalTokensForRepay),
                address(_token2),
                address(_token1)
            );
            _swap(amountToSwap, address(_token2), address(_token1));
        }
    }

    function closePosition(uint sharesPercentage) external {
        _removeLiquidity(sharesPercentage);
        AccountSnapshot memory accountSnapshot0 = getAccountSnapshot();
        _checkForAdditionalSwap(accountSnapshot0, sharesPercentage);
        AccountSnapshot memory accountSnapshot = getAccountSnapshot();
        _soToken2.repayBorrow(
            (1000000 * (accountSnapshot.borrowBalance * sharesPercentage)) /
                1e24
        );
        _soToken1.redeemUnderlying(
            (accountSnapshot.supplyBalance * sharesPercentage) / 1e18
        );
        _swap(
            _token1.balanceOf(address(this)),
            address(_token1),
            address(_token2)
        );
    }

    function getTotalAmount() public view returns (uint totalAmount) {
        AccountSnapshot memory snapshot = getAccountSnapshot();
        return snapshot.totalAmount;
    }

    function getAccountSnapshot() public view returns (AccountSnapshot memory) {
        AccountSnapshot memory snapshot;
        uint err1;
        (uint err, uint supply, , uint mantissa) = _soToken1.getAccountSnapshot(
            address(this)
        );
        require(err == 0, "error in getting account snapshot");
        (err1, , snapshot.borrowBalance, ) = _soToken2.getAccountSnapshot(
            address(this)
        );
        require(err1 == 0, "error in getting account snapshot");
        snapshot.supplyBalance = (mantissa * supply) / 1e18;
        uint reserves1;
        uint reserves2;
        (
            snapshot.LPToken1Amount,
            snapshot.LPToken2Amount,
            reserves1,
            reserves2
        ) = _getReserves(addresses.poolTokenAddress);
        (uint price1, uint price2) = _getOraclePrices(_soToken1, _soToken2);
        snapshot.supplyBalanceUSD = (snapshot.supplyBalance * price1) / 1e30;
        snapshot.borrowBalanceUSD = (snapshot.borrowBalance * price2) / 1e30;

        uint token1LpUSD = (snapshot.LPToken2Amount * price1) / 1e30;
        uint token2LpUSD = (snapshot.LPToken1Amount * price2) / 1e30;
        snapshot.LPBalanceUSD = token1LpUSD + token2LpUSD;
        snapshot.totalAmount = (snapshot.supplyBalanceUSD -
            snapshot.borrowBalanceUSD +
            snapshot.LPBalanceUSD);
        if (snapshot.borrowBalanceUSD > 0 && snapshot.LPBalanceUSD > 0) {
            snapshot.hedgingPercentageCurrent =
                (2 * 1e18 * snapshot.borrowBalanceUSD) /
                (snapshot.LPBalanceUSD);
            snapshot.healthFactorCurrent =
                (snapshot.supplyBalanceUSD * params.collateralFactor) /
                snapshot.borrowBalanceUSD;
        }
        return snapshot;
    }

    function _getReserves(
        address poolToken
    )
        internal
        view
        returns (
            uint LPToken1Amount,
            uint LPToken2Amount,
            uint reserves1,
            uint reserves2
        )
    {
        IPool poolTokenContract = IPool(poolToken);
        uint poolTokenBalance = poolTokenContract.balanceOf(address(this)) +
            IGauge(addresses.poolTokenGauge).balanceOf(address(this));
        (reserves1, reserves2, ) = poolTokenContract.getReserves();
        uint poolTokenTotalSupply = poolTokenContract.totalSupply();
        LPToken1Amount = poolTokenBalance * (reserves1 / poolTokenTotalSupply);
        LPToken2Amount =
            (poolTokenBalance * ((1e12 * reserves2) / poolTokenTotalSupply)) /
            1e12;
        return (LPToken1Amount, LPToken2Amount, reserves1, reserves2);
    }

    function claimAndReinvest() external returns (uint balanceChange) {
        uint preTotalAmount = getTotalAmount();
        CToken[] memory cTokens = new CToken[](2);
        cTokens[0] = CToken(address(_soToken1));
        cTokens[1] = CToken(address(_soToken2));
        Iunitroller(addresses.unitroller).claimComp(address(this), cTokens);
        uint sonneBalance = IERC20(addresses.SONNEaddress).balanceOf(
            address(this)
        );
        IGauge _gauge = IGauge(addresses.poolTokenGauge);
        address veloToken = _gauge.rewardToken();
        console.log("balanceOf", _gauge.balanceOf(address(this)));
        console.log("earned", _gauge.earned(address(this)));
        console.log("veloToken", veloToken);
        _gauge.getReward(address(this));
        uint veloBalance = IERC20(veloToken).balanceOf(address(this));
        console.log("velo balance", veloBalance);
        console.log("sonne balance", sonneBalance);
        IERC20(addresses.SONNEaddress).approve(
            address(addresses.veloRouter),
            sonneBalance
        );
        IERC20(veloToken).approve(address(addresses.veloRouter), veloBalance);
        IveloRouter.Route[] memory sonneRoute = new IveloRouter.Route[](1);
        sonneRoute[0] = IveloRouter.Route({
            from: addresses.SONNEaddress,
            to: addresses.InitTokenAddress,
            stable: false,
            factory: addresses.veloFactory
        });
        IveloRouter.Route[] memory veloRoute = new IveloRouter.Route[](1);
        veloRoute[0] = IveloRouter.Route({
            from: veloToken,
            to: addresses.InitTokenAddress,
            stable: false,
            factory: addresses.veloFactory
        });
        uint256[] memory amountssonne = IveloRouter(addresses.veloRouter)
            .getAmountsOut(sonneBalance, sonneRoute);
        uint sonneAmount = amountssonne[1];
        require(sonneAmount > 0, "bad sonne swap");
        uint256[] memory amountsvelo = IveloRouter(addresses.veloRouter)
            .getAmountsOut(veloBalance, veloRoute);
        uint veloAmount = amountsvelo[1];
        require(veloAmount > 0, "bad velo swap");
        IveloRouter(addresses.veloRouter).swapExactTokensForTokens(
            sonneBalance,
            sonneAmount,
            sonneRoute,
            address(this),
            block.timestamp + 6
        );
        IveloRouter(addresses.veloRouter).swapExactTokensForTokens(
            veloBalance,
            veloAmount,
            veloRoute,
            address(this),
            block.timestamp + 6
        );
        _getIntoPosition(_initToken.balanceOf(address(this)), false);
        uint postTotalAmount = getTotalAmount();
        return (postTotalAmount - preTotalAmount);
    }
}
