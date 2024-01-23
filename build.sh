#!/bin/sh

set -eu

forge test -R @uniswap/v4-core/contracts=./deps/v4-core/src -R @openzeppelin/contracts=./deps/openzeppelin-contracts/contracts --contracts $1
