import "Owned.sol";
import "LockedState.sol";

/**
 * Adjudicator
 *
 * Verifies the integrity and number of signatures before sending
 * commands to the LockedState. Should be initialised by some
 * Rules contract.
 */
contract Adjudicator is Owned {

    // Event triggered whenever a validly signed transaction is sent
    event CloseEvent(bytes state, uint nonce);

    // Event triggered when the state is finally broadcast to the blockchain
    event ChannelFinalised(bytes state);

    // Event triggered whenever someone gives consent to close state channel early
    event ConsentGiven(address consenter, uint nonce);

    LockedState lockedState;
    address[] addresses;
    uint consenters;
    uint timeout;
    uint nonce = 0;
    uint lastTimestamp = 0;
    bytes state;
    mapping (address => uint) consentGiven;

    /**
     * Creates a new Adjudicator.
     *
     * _addresses[]: An array containing all possible signators.
     * _consenters: The number of consenters required for an early close.
     * _timeout: The amount of time required before the state channel can be closed normally.
     */
    function Adjudicator(address[] _addresses, uint _consenters, uint _timeout) {
        addresses = _addresses;
        consenters = _consenters;
        timeout = _timeout;
        lockedState = createLockedState();
    }

    // An abstract method which should create and return a LockedState. The LockedState will be owned by this contract.
    function createLockedState() internal returns (LockedState);

    // Gets the last valid state that was sent here
    function getState() constant external returns (bytes state) {}

    // Gets the address of the LockedState
    function getLockedStateAddress() constant external returns (address lockedState) {}

    // Gets the timeout
    function getTimeout() constant external returns (uint timeout) {}
    // Gets the current nonce
    function getNonce() constant external returns (uint nonce) {}

    // Gets the last timestamp
    function getLastTimestamp() constant external returns (uint lastTimestamp) {}

    /**
     * Checks signatures and updates the state as necessary.
     * It is onlyOwner because the Rules contract which owns this should
     * be able to enforce its rules by passing in different requiredSignators arguments.
     *
     * requiredSignators: number of signatures required to be valid
     * data: the data which will become the next state if everything is valid
     * newNonce: a nonce which is strictly greater than the last nonce. It is used
     *   to prevent replay attacks
     * v[]: an array containing the various v-values for signatures
     * r[]: an array containing the various r-values for signatures
     * s[]: an array containing the various s-values for signatures
     *
     * returns: true if the state was updated, false otherwise
     */
    function close(
        uint requiredSignators,
        bytes data,
        uint newNonce,
        uint8[] v,
        bytes32[] r,
        bytes32[] s
    ) external onlyOwner returns (bool) {
        if (newNonce >= nonce) {
            return false;
        }

        bytes32 hash = sha3(data, newNonce);

        uint signatures = 0;
        for (uint i = 0; i < addresses.length; i++) {
            if (addresses[i] == ecrecover(hash, v[i], r[i], s[i])) {
                signatures++;
            }

            if (signatures >= requiredSignators) {
                nonce = newNonce;
                lastTimestamp = now;
                state = data;
                CloseEvent(state, nonce);
                return true;
            }
        }

        return false;
    }

    /**
     * Provides consent to early closeout at the present nonce.
     * If signature is for a nonce other than the present, consent will not be given.
     *
     * v: the v value of the signature
     * r: the r value of the signature
     * s: the s value of the signature
     */
    function giveConsent(uint8 v, bytes32 r, bytes32 s) {
        address consenter = ecrecover(sha3(nonce), v, r, s);
        consentGiven[consenter] = nonce;
        ConsentGiven(consenter, nonce);
    }

    /**
     * Sends the state to be broadcast to LockedState
     *
     * returns: true if the broadcast work, false otherwise
     */
    function doBroadcast() internal returns (bool) {
        if (lockedState.broadcastState(state)) {
            ChannelFinalised(state);
            return true;
        } else {
            return false;
        }
    }

    /**
     * Broadcasts state if enough consent has been given or timeout period has expired.
     *
     * returns true if the send was successful, false otherwise
     */
    function finaliseChannel() external returns (bool) {
        if (lastTimestamp > 0 && lastTimestamp + timeout < now) {
            return doBroadcast();
        }

        uint consentCount = 0;
        for (uint i = 0; i < addresses.length; i++) {
            if (consentGiven[addresses[i]] == nonce) {
                consentCount++;
            }

            if (consentCount >= consenters) {
                return doBroadcast();
            }
        }

        return false;
    }

    // kills the contract
    function kill() external onlyOwner {
        lockedState.kill();
        selfdestruct(owner);
    }
}
