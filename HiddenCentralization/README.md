# Vulnerability Pattern 5 - Hidden Centralization

## Issue

Unlike the other issues listed here, this is not a security vulnerability in the contract. However, it is worth discussing since it introduces uniswap AMM trust model changes.

For earlier versions of uniswap, pool deployers hold minimal control over the pool once created. This means that users do not have to worry about centralization issues that may result in rug pulls or other human-based mismanagement. However, the introduction of hooks changes this. High flexibility comes with a price; now, each pool may be accompanied by its own hook contract, which may include admin roles.

While contract centralization is nothing new in the DeFi landscape, it is new to uniswap, and users must be aware of this to prevent suffering from loss. The responsibility is not on individual users to check the hook contract implementation before every pool action.

In our example [vuln.sol](), we present a case where admins may upgrade from V1 to V2 contracts to halt the entire pool, effectively taking all funds within it hostage. This simple example shows how privileged roles introduce new risks for users. Attacks do not stop at DoS; with a little more effort, fund-stealing hooks may easily be implemented.
## Mitigation

Since this is not a vulnerability in the contract, there is no real mitigation against it, except for requiring users to do their research before utilizing contracts.

In practice, privileged roles do not necessarily mean the actors are malicious parties. Those roles may be used to take action when security incidents occur or as governance to ensure the protocol's well-being.

Nonetheless, if hook developers wish to minimize such risk, the best approach would be to eliminate privileged roles.

