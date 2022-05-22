// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {ICollectModule} from '../../../interfaces/ICollectModule.sol';
import {Errors} from '../../../libraries/Errors.sol';
import {FeeModuleBase} from '../FeeModuleBase.sol';
import {ModuleBase} from '../ModuleBase.sol';
import {FollowValidationModuleBase} from '../FollowValidationModuleBase.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';

import "hardhat/console.sol";

/**
 * @notice A struct containing the necessary data to execute collect actions on a publication.
 *
 * @param collectLimit The maximum number of collects for this publication.
 * @param currentCollects The current number of collects for this publication.
 * @param amount The collecting cost associated with this publication.
 * @param currency The currency associated with this publication.
 * @param recipient The recipient address associated with this publication.
 * @param referralFee The referral fee associated with this publication.
 * @param followerOnly Whether only followers should be able to collect.
 */
    struct ProfilePublicationData {
        bool isValid;

        uint256 collectLimit;
        uint256 currentCollects;
        uint256 amount;
        address currency;
        address recipient;
        uint16 referralFee;
        bool followerOnly;

        uint16 favs;  // Likes are coming to lens propper eventually
        uint16 plays;
    }

/**
* @notice A struct containing the state necessary for the front-end functionality.
*
* @param purchaseDate   The date when collect was done - the song attached to the publication was bought
* @param openDate   The date when a collect received by dm was initially opened
* @param used   True when the song attached to the publication was used by the receiver
* @param downloaded     True when the song attached to the publication was downloaded
*/
    struct ProfileStateData {
        bool isValid;

        uint256 purchaseDate;
        uint256 openDate;
        bool used;
        bool downloaded;
    }

/**
 * @title LimitedFeeCollectModule
 * @author Lens Protocol
 *
 * @notice This is a simple Lens CollectModule implementation, inheriting from the ICollectModule interface and
 * the FeeCollectModuleBase abstract contract.
 *
 * This module works by allowing limited collects for a publication indefinitely.
 */
contract BtraxCollectModule is FeeModuleBase, FollowValidationModuleBase, ICollectModule {
    using SafeERC20 for IERC20;

    event CollectedStateUpdated(address collector, uint256 profileId, uint256 pubId,
        uint256 openDate, uint256 purchaseDate, uint16 favs, uint16 plays, bool used, bool downloaded);

    mapping(uint256 => mapping(uint256 => ProfilePublicationData)) internal _dataByPublicationByProfile;
    mapping(uint256 => mapping(uint256 => mapping(address => ProfileStateData))) internal _stateByCollector;

    mapping(address => bool) internal _favoritedAddresses;


    constructor(address hub, address moduleGlobals) FeeModuleBase(moduleGlobals) ModuleBase(hub) {}

    /**
     * @notice This collect module levies a fee on collects and supports referrals. Thus, we need to decode data.
     *
     * @param profileId The profile ID of the publication to initialize this module for's publishing profile.
     * @param pubId The publication ID of the publication to initialize this module for.
     * @param data The arbitrary data parameter, decoded into:
     *      uint256 collectLimit: The maximum amount of collects.
     *      uint256 amount: The currency total amount to levy.
     *      address currency: The currency address, must be internally whitelisted.
     *      address recipient: The custom recipient address to direct earnings to.
     *      uint16 referralFee: The referral fee to set.
     *      bool followerOnly: Whether only followers should be able to collect.
     *
     * @return bytes An abi encoded bytes parameter, which is the same as the passed data parameter.
     */
    function initializePublicationCollectModule(
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) external override onlyHub returns (bytes memory) {
        (
        uint256 collectLimit,
        uint256 amount,
        address currency,
        address recipient,
        uint16 referralFee,
        bool followerOnly
        ) = abi.decode(data, (uint256, uint256, address, address, uint16, bool));

        if (
            collectLimit == 0 ||
            !_currencyWhitelisted(currency) ||
            recipient == address(0) ||
            referralFee > BPS_MAX ||
            amount == 0
        ) revert Errors.InitParamsInvalid();

        _dataByPublicationByProfile[profileId][pubId].collectLimit = collectLimit;
        _dataByPublicationByProfile[profileId][pubId].amount = amount;
        _dataByPublicationByProfile[profileId][pubId].currency = currency;
        _dataByPublicationByProfile[profileId][pubId].recipient = recipient;
        _dataByPublicationByProfile[profileId][pubId].referralFee = referralFee;
        _dataByPublicationByProfile[profileId][pubId].followerOnly = followerOnly;  // Will likely be hardcoded to true

        return data;
    }

    /**
     * @dev Processes a collect by:
     *  1. Ensuring the collector is a follower
     *  2. Ensuring the collect does not pass the collect limit
     *  3. Charging a fee
     */
    function processCollect(
        uint256 referrerProfileId,
        address collector,
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) external override onlyHub {
        if (_dataByPublicationByProfile[profileId][pubId].followerOnly)
            _checkFollowValidity(profileId, collector);

        if (_dataByPublicationByProfile[profileId][pubId].currentCollects >=
                    _dataByPublicationByProfile[profileId][pubId].collectLimit) {
            revert Errors.MintLimitExceeded();
        } else {
            _stateByCollector[profileId][pubId][collector].isValid = true;
            _stateByCollector[profileId][pubId][collector].purchaseDate = block.timestamp;

            _dataByPublicationByProfile[profileId][pubId].isValid = true;
            ++_dataByPublicationByProfile[profileId][pubId].currentCollects;

            if (referrerProfileId == profileId) {
                _processCollect(collector, profileId, pubId, data);
            } else {
                _processCollectWithReferral(referrerProfileId, collector, profileId, pubId, data);
            }
        }
    }

    /**
     * @notice Returns the publication data for a given publication, or an empty struct if that publication was not
     * initialized with this module.
     *
     * @param profileId The token ID of the profile mapped to the publication to query.
     * @param pubId The publication ID of the publication to query.
     *
     * @return ProfilePublicationData The ProfilePublicationData struct mapped to that publication.
     */
    function getPublicationData(uint256 profileId, uint256 pubId) external view returns (ProfilePublicationData memory) {
        return _dataByPublicationByProfile[profileId][pubId];
    }

    /**
     * @notice Returns the state for a given publication and sender, or an empty struct if the publication was not
     * initialized with this module.
     *
     * @param profileId The token ID of the profile mapped to the publication to query.
     * @param pubId The publication ID of the publication to query.
     *
     * @return ProfileStateData     The state mapped to that publication
     */
    function getStateData(uint256 profileId, uint256 pubId) external view returns (ProfileStateData memory) {
        return _stateByCollector[profileId][pubId][msg.sender];
    }

    function setOpened(uint256 profileId, uint256 pubId) public {
        require(_dataByPublicationByProfile[profileId][pubId].isValid, "Publication doesn't exist");  // Create modifier
        require(_stateByCollector[profileId][pubId][msg.sender].isValid, "Only collector can open a beat");

        if (_stateByCollector[profileId][pubId][msg.sender].openDate == 0) {
            _stateByCollector[profileId][pubId][msg.sender].openDate = block.timestamp;
            emitStatusChangedEvent(profileId, pubId);
        }
    }

    function updateFavs(uint256 profileId, uint256 pubId, bool isFavourite) public {
        require(_dataByPublicationByProfile[profileId][pubId].isValid, "Publication doesn't exist");
        require(isFavourite == true && _favoritedAddresses[msg.sender], "Already favorited");

        if (isFavourite) {
            _favoritedAddresses[msg.sender] = true;
            ++_dataByPublicationByProfile[profileId][pubId].favs;
        } else {
            delete _favoritedAddresses[msg.sender];
            --_dataByPublicationByProfile[profileId][pubId].favs;
        }

        emitStatusChangedEvent(profileId, pubId);
    }

    function updatePlays(uint256 profileId, uint256 pubId) public {
        require(_dataByPublicationByProfile[profileId][pubId].isValid, "Publication doesn't exist");

        ++_dataByPublicationByProfile[profileId][pubId].plays;
        emitStatusChangedEvent(profileId, pubId);
    }

    function updateUsed(uint256 profileId, uint256 pubId, bool isUsed) public {
        require(_dataByPublicationByProfile[profileId][pubId].isValid, "Publication doesn't exist");
        require(_stateByCollector[profileId][pubId][msg.sender].isValid, "Only collector can use a beat");

        _stateByCollector[profileId][pubId][msg.sender].used = isUsed;
        emitStatusChangedEvent(profileId, pubId);
    }

    function updateDownloaded(uint256 profileId, uint256 pubId) public {
        require(_dataByPublicationByProfile[profileId][pubId].isValid, "Publication doesn't exist");
        require(_stateByCollector[profileId][pubId][msg.sender].isValid, "Only collector can download a beat");

        _stateByCollector[profileId][pubId][msg.sender].downloaded = true;
        emitStatusChangedEvent(profileId, pubId);
    }

    function emitStatusChangedEvent(uint256 profileId, uint256 pubId) private {
        emit CollectedStateUpdated(
            msg.sender, profileId, pubId,

            _stateByCollector[profileId][pubId][msg.sender].openDate,
            _stateByCollector[profileId][pubId][msg.sender].purchaseDate,

            _dataByPublicationByProfile[profileId][pubId].favs,
            _dataByPublicationByProfile[profileId][pubId].plays,

            _stateByCollector[profileId][pubId][msg.sender].used,
            _stateByCollector[profileId][pubId][msg.sender].downloaded
        );
    }

    function _processCollect(
        address collector,
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) internal {
        uint256 amount = _dataByPublicationByProfile[profileId][pubId].amount;
        address currency = _dataByPublicationByProfile[profileId][pubId].currency;
        _validateDataIsExpected(data, currency, amount);

        (address treasury, uint16 treasuryFee) = _treasuryData();
        address recipient = _dataByPublicationByProfile[profileId][pubId].recipient;
        uint256 treasuryAmount = (amount * treasuryFee) / BPS_MAX;
        uint256 adjustedAmount = amount - treasuryAmount;

        IERC20(currency).safeTransferFrom(collector, recipient, adjustedAmount);
        if (treasuryAmount > 0)
            IERC20(currency).safeTransferFrom(collector, treasury, treasuryAmount);
    }

    function _processCollectWithReferral(
        uint256 referrerProfileId,
        address collector,
        uint256 profileId,
        uint256 pubId,
        bytes calldata data
    ) internal {
        uint256 amount = _dataByPublicationByProfile[profileId][pubId].amount;
        address currency = _dataByPublicationByProfile[profileId][pubId].currency;
        _validateDataIsExpected(data, currency, amount);

        uint256 referralFee = _dataByPublicationByProfile[profileId][pubId].referralFee;
        address treasury;
        uint256 treasuryAmount;

        // Avoids stack too deep
        {
            uint16 treasuryFee;
            (treasury, treasuryFee) = _treasuryData();
            treasuryAmount = (amount * treasuryFee) / BPS_MAX;
        }

        uint256 adjustedAmount = amount - treasuryAmount;

        if (referralFee != 0) {
            // The reason we levy the referral fee on the adjusted amount is so that referral fees
            // don't bypass the treasury fee, in essence referrals pay their fair share to the treasury.
            uint256 referralAmount = (adjustedAmount * referralFee) / BPS_MAX;
            adjustedAmount = adjustedAmount - referralAmount;

            address referralRecipient = IERC721(HUB).ownerOf(referrerProfileId);

            IERC20(currency).safeTransferFrom(collector, referralRecipient, referralAmount);
        }
        address recipient = _dataByPublicationByProfile[profileId][pubId].recipient;

        IERC20(currency).safeTransferFrom(collector, recipient, adjustedAmount);
        if (treasuryAmount > 0)
            IERC20(currency).safeTransferFrom(collector, treasury, treasuryAmount);
    }
}
