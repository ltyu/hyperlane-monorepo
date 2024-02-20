// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.13;

import {Test, StdStorage, stdStorage} from "forge-std/Test.sol";
import {Message} from "../../contracts/libs/Message.sol";

import {TypeCasts} from "../../contracts/libs/TypeCasts.sol";
import {MessageUtils} from "../isms/IsmTestUtils.sol";
import {MockMailbox} from "../../contracts/mock/MockMailbox.sol";
import {TelepathyCcipReadIsm} from "../../contracts/isms/ccip-read/telepathy/TelepathyCcipReadIsm.sol";
import {TelepathyCcipReadHook} from "../../contracts/hooks/ccip/TelepathyCcipReadHook.sol";
import {ICcipReadIsm} from "../../contracts/interfaces/isms/ICcipReadIsm.sol";
import {StateProofHelpersTest} from "../lib/StateProofHelpers.t.sol";
import {ISuccinctProofsService} from "../../contracts/interfaces/ccip-gateways/ISuccinctProofsService.sol";

contract TelepathyCcipReadIsmTest is StateProofHelpersTest {
    using Message for bytes;
    using stdStorage for StdStorage;
    using TypeCasts for address;

    address internal alice = address(0x1);
    string[] urls = ["localhost:3001/telepathy-ccip/"];

    MockMailbox mailbox;
    TelepathyCcipReadIsm internal telepathyCcipReadIsm;
    TelepathyCcipReadHook internal hook;

    function setUp() public override {
        super.setUp();
        telepathyCcipReadIsm = new TelepathyCcipReadIsm({
            genesisValidatorsRoot: EMPTY_BYTES32,
            genesisTime: 0,
            secondsPerSlot: 12,
            slotsPerPeriod: 8192,
            syncCommitteePeriod: 0,
            syncCommitteePoseidon: EMPTY_BYTES32,
            sourceChainId: 1,
            finalityThreshold: 461,
            stepFunctionId: EMPTY_BYTES32,
            rotateFunctionId: EMPTY_BYTES32,
            gatewayAddress: address(5)
        });
        deployCodeTo("TelepathyCcipReadHook.sol", abi.encode(0), HOOK_ADDR);
        mailbox = MockMailbox(MAILBOX_ADDR);
        hook = TelepathyCcipReadHook(HOOK_ADDR);

        telepathyCcipReadIsm.initialize(
            mailbox,
            mailbox,
            hook,
            DISPATCHED_SLOT,
            urls
        );

        _setExecutionStateRoot();
    }

    // ============ Helper Functions ============

    function _encodeTestMessage(
        uint32 _messageNonce
    ) internal pure returns (bytes memory) {
        return
            MessageUtils.formatMessage(
                0,
                _messageNonce,
                0,
                hex"0000000000000000000000007fa9385be102ac3eac297483dd6233d62b3e1496",
                0,
                hex"0000000000000000000000007fa9385be102ac3eac297483dd6233d62b3e1496",
                hex"00000000000000000000000000000000000000000000000000000000000000a7"
            );
    }

    function _copyUrls() internal view returns (string[] memory offChainUrls) {
        uint256 len = telepathyCcipReadIsm.offchainUrlsLength();
        offChainUrls = new string[](len);
        for (uint256 i; i < len; i++) {
            offChainUrls[i] = telepathyCcipReadIsm.offchainUrls(i);
        }
    }

    /// @dev This Mocks what Succinct's Prover will set. In the future, we can get a proof from Succient and make this test a bit better by calling step()
    function _setExecutionStateRoot() internal {
        // Set the head slot
        stdstore
            .target(address(telepathyCcipReadIsm))
            .sig("head()")
            .checked_write(1);

        // Set the head slot to stateRoot
        stdstore
            .target(address(telepathyCcipReadIsm))
            .sig("executionStateRoots(uint256)")
            .with_key(1)
            .depth(0)
            .checked_write(stateRoot);
    }

    function _encodeProofs() internal view returns (bytes memory) {
        return abi.encode(accountProof, storageProof);
    }

    function testTelepathyCcip_setOffchainUrls_revertsWithNonOwner(
        address _nonOwner
    ) public {
        vm.assume(_nonOwner != address(this));

        urls.push("localhost:3001/telepathy-ccip-2/");
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(_nonOwner);
        telepathyCcipReadIsm.setOffchainUrls(urls);

        // Default to owner
        telepathyCcipReadIsm.setOffchainUrls(urls);
        assertEq(telepathyCcipReadIsm.offchainUrlsLength(), 2);
    }

    function testTelepathyCcip_getOffchainVerifyInfo_revertsCorrectly(
        uint32 _messageNonce
    ) public {
        bytes memory encodedMessage = _encodeTestMessage(_messageNonce);
        string[] memory offChainUrls = _copyUrls();
        bytes memory offChainLookupError = abi.encodeWithSelector(
            ICcipReadIsm.OffchainLookup.selector,
            address(telepathyCcipReadIsm),
            offChainUrls,
            abi.encodeWithSelector(
                ISuccinctProofsService.getProofs.selector,
                address(HOOK_ADDR),
                telepathyCcipReadIsm.dispatchedSlotKey(_messageNonce),
                1
            ), // Mailbox Addr, storageKeys, blockNumber
            TelepathyCcipReadIsm.process.selector,
            encodedMessage
        );
        vm.expectRevert(offChainLookupError);
        telepathyCcipReadIsm.getOffchainVerifyInfo(encodedMessage);
    }

    function testTelepathyCcip_verify_withMessage(
        uint32 _incorrectMessageNonce
    ) public {
        vm.assume(_incorrectMessageNonce != MESSAGE_NONCE);

        // Incorrect message
        bool verified = telepathyCcipReadIsm.verify(
            _encodeProofs(),
            _encodeTestMessage(_incorrectMessageNonce)
        );
        assertFalse(verified);

        // Correct message
        verified = telepathyCcipReadIsm.verify(
            _encodeProofs(),
            _encodeTestMessage(MESSAGE_NONCE)
        );
        assertTrue(verified);
    }
}
