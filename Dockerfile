# Use the latest foundry image
FROM ghcr.io/foundry-rs/foundry

ARG poc_path="./bugs/"

# Copy our source code into the container
WORKDIR /app
COPY . .

RUN git config --global user.name "abc"
RUN git config --global user.email "abc@example.com"

# Install libraries
RUN forge install https://github.com/Uniswap/v4-core@06564d33b2fa6095830c914461ee64d34d39c305
RUN forge install openzeppelin/openzeppelin-contracts --no-commit

RUN chmod +x build.sh

#RUN forge test --contracts ./bugs/

# Execute POC
RUN ./build.sh $poc_path
