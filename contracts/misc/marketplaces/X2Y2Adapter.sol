// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {DataTypes} from "../../protocol/libraries/types/DataTypes.sol";
import {Errors} from "../../protocol/libraries/helpers/Errors.sol";
import {ILooksRareExchange} from "../../dependencies/looksrare/contracts/interfaces/ILooksRareExchange.sol";
import {IX2Y2} from "../../interfaces/IX2Y2.sol";
import {ConsiderationItem, OfferItem, ItemType} from "../../dependencies/seaport/contracts/lib/ConsiderationStructs.sol";
import {Address} from "../../dependencies/openzeppelin/contracts/Address.sol";
import {IMarketplace} from "../../interfaces/IMarketplace.sol";
import {IPoolAddressesProvider} from "../../interfaces/IPoolAddressesProvider.sol";

/**
 * @title X2Y2 Adapter
 *
 * @notice Implements the NFT <=> ERC20 exchange logic via X2Y2 marketplace
 */
contract X2Y2Adapter is IMarketplace {
    IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;

    constructor(IPoolAddressesProvider provider) {
        ADDRESSES_PROVIDER = provider;
    }

    struct ERC721Pair {
        address token;
        uint256 tokenId;
    }

    function getAskOrderInfo(bytes memory params)
        external
        pure
        override
        returns (DataTypes.OrderInfo memory orderInfo)
    {
        IX2Y2.RunInput memory runInput = abi.decode(params, (IX2Y2.RunInput));
        require(runInput.details.length == 1, Errors.INVALID_MARKETPLACE_ORDER);

        IX2Y2.SettleDetail memory detail = runInput.details[0];
        IX2Y2.SettleShared memory shared = runInput.shared;
        IX2Y2.Order memory order = runInput.orders[detail.orderIdx];
        IX2Y2.OrderItem memory item = order.items[detail.itemIdx];

        require(
            shared.amountToWeth == 0 && shared.amountToEth == 0, // dont rely on x2y2 for ETH/WETH convention
            Errors.INVALID_MARKETPLACE_ORDER
        );
        require(
            !shared.canFail && IX2Y2.Op.COMPLETE_SELL_OFFER == detail.op,
            Errors.INVALID_MARKETPLACE_ORDER
        );

        ERC721Pair[] memory nfts = abi.decode(item.data, (ERC721Pair[]));

        require(nfts.length == 1, Errors.INVALID_MARKETPLACE_ORDER);

        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItem(
            ItemType.ERC721,
            nfts[0].token,
            nfts[0].tokenId,
            1,
            1
        );
        orderInfo.offer = offer;

        ConsiderationItem[] memory consideration = new ConsiderationItem[](1);

        ItemType itemType = ItemType.ERC20;
        address token = order.currency;
        consideration[0] = ConsiderationItem(
            itemType,
            token,
            0,
            detail.price,
            detail.price,
            payable(order.user)
        );
        orderInfo.id = abi.encodePacked(order.r, order.s, order.v);
        orderInfo.consideration = consideration;
    }

    function getBidOrderInfo(bytes memory)
        external
        pure
        override
        returns (DataTypes.OrderInfo memory)
    {
        revert(Errors.CALL_MARKETPLACE_FAILED);
    }

    function matchAskWithTakerBid(
        address marketplace,
        bytes calldata params,
        uint256 value
    ) external payable override returns (bytes memory) {
        bytes4 selector = IX2Y2.run.selector;
        bytes memory data = abi.encodePacked(selector, params);
        return
            Address.functionCallWithValue(
                marketplace,
                data,
                value,
                Errors.CALL_MARKETPLACE_FAILED
            );
    }

    function matchBidWithTakerAsk(address, bytes calldata)
        external
        pure
        override
        returns (bytes memory)
    {
        revert(Errors.CALL_MARKETPLACE_FAILED);
    }
}
