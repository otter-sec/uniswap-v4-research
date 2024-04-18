# v4-template

## Execute PoC:

### Via Docker

After clonning the repo, run the dockerfile to execute a PoC:

```bash
docker build --no-cache --progress=plain --build-arg poc_path="./bugs/<folder-name>/PoC.sol" -t hooks . 
```
> Note: If the `poc_path` arguments is not specified, all PoC's will be executed by default.

### Via shell script

After clonning the repo, install the necessary dependencies:

```bash
forge install https://github.com/Uniswap/v4-core@06564d33b2fa6095830c914461ee64d34d39c305

forge install openzeppelin/openzeppelin-contracts
```
Once these dependencies are installed, the PoC may be executed via the `build.sh` shell script by supplying the path to the specific PoC as an argument:

```bash
chmod +x build.sh

./build.sh ./bugs/<folder-name>/PoC.sol
```
