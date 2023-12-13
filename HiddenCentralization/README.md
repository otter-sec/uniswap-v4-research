# Vulnerability Pattern 5 - Hidden Centralization

## Issue

A bit different from the other issues listed here, this one is not a security bug in the contract. However, we find it worthy of discussing here since it introduces changes in the uniswap AMM trust model.

For earlier versions of uniswap, pool deployers have minimal control over the pool once it is created. This means that users do not have to worry about centralization issues that may lead to rug pulls or other human based mismanagement. However, the introduction of hooks changes this. High flexibility comes with a price, now each pool may be accompanied by its own hook contract, which may include admin roles. 

While contract centralization is nothing new in the DeFi landscape, it is new to uniswap, and users must be aware of this to prevent suffering from loss. The responsibility is not on individual users to check the hook contract implementation before each and every pool actions. 

In our example [vuln.sol](), we present a case where admins may upgrade from V1 to V2 contracts to halt the entire pool, effectively taking all funds within it hostage. This is a pretty simple example which shows how privileged roles introduce new risks for users. And attacks do not stop at DoS, with a little bit more effort, fund stealing hooks can be easily implemented.

## Mitigation

Since this is not a vulnerability in the contract, there is no real mitigation against it, except for requiring users to do their own research before using contracts. 

In practice, privileged roles do not necessarily mean malicious parties. Those roles may be used to take actions when security incidence happens, or as governance to ensure the well-standing of the protocol.

Nonetheless, if hook developers want to minimize such risk, the best approach would be to get rid of privileged roles altogether.

## In the wild examples
