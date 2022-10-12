#!/bin/bash

# Drivechain integration testing

# This script will download and build the mainchain and testchain and run a
# series of tests

#
# Warn user, delete old data, clone repositories
#

# VERSION 2 TODO:
# * Make mining a block & BMM mining functions
#
# * After the first test, repeat the same tests again but with 2 sidechains
# active at the same time.
#
# * Then do some tests sending deposits and creating withdrawals from both
# sidechains. Do a test where a deposit is made to the first sidechain,
# withdrawn, and then sent to the second sidechain and withdrawn again.
#
# * Keep track of balances and make sure that no funds are lost to BMM - make
# sure that 100% of funds from failed BMM txns are recovered
#
# * Test a sidechain withdrawal failing
#
# * Test multiple withdrawals at once for two sidechains
#
VERSION=1

REINDEX=0
BMM_BID=0.0001
MIN_WORK_SCORE=131
SIDECHAIN_ACTIVATION_SCORE=20

# Read arguments
SKIP_CLONE=0 # Skip cloning the repositories from github
SKIP_BUILD=0 # Skip pulling and building repositories
SKIP_CHECK=0 # Skip make check on repositories
SKIP_REPLACE_TIP=0 # Skip tests where we replace the chainActive.Tip()
SKIP_RESTART=0 # Skip tests where we restart and verify state after restart
SKIP_SHUTDOWN=0 # Don't shutdown the main & side clients when finished testing
INCOMPATIBLE_BDB=0 # Compile --with-incompatible-bdb
for arg in "$@"
do
    if [ "$arg" == "--help" ]; then
        echo "The following command line options are available:"
        echo "--skip_clone"
        echo "--skip_build"
        echo "--skip_check"
        echo "--skip_replace_tip"
        echo "--skip_restart"
        echo "--skip_shutdown"
        echo "--with-incompatible-bdb"
        exit
    elif [ "$arg" == "--skip_clone" ]; then
        SKIP_CLONE=1
    elif [ "$arg" == "--skip_build" ]; then
        SKIP_BUILD=1
    elif [ "$arg" == "--skip_check" ]; then
        SKIP_CHECK=1
    elif [ "$arg" == "--skip_replace_tip" ]; then
        SKIP_REPLACE_TIP=1
    elif [ "$arg" == "--skip_restart" ]; then
        SKIP_RESTART=1
    elif [ "$arg" == "--skip_shutdown" ]; then
        SKIP_SHUTDOWN=1
    elif [ "$arg" == "--with-incompatible-bdb" ]; then
        INCOMPATIBLE_BDB=1
    fi
done

clear

echo -e "\e[36m██████╗ ██████╗ ██╗██╗   ██╗███████╗███╗   ██╗███████╗████████╗\e[0m"
echo -e "\e[36m██╔══██╗██╔══██╗██║██║   ██║██╔════╝████╗  ██║██╔════╝╚══██╔══╝\e[0m"
echo -e "\e[36m██║  ██║██████╔╝██║██║   ██║█████╗  ██╔██╗ ██║█████╗     ██║\e[0m"
echo -e "\e[36m██║  ██║██╔══██╗██║╚██╗ ██╔╝██╔══╝  ██║╚██╗██║██╔══╝     ██║\e[0m"
echo -e "\e[36m██████╔╝██║  ██║██║ ╚████╔╝ ███████╗██║ ╚████║███████╗   ██║\e[0m"
echo -e "\e[36m╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝╚══════╝   ╚═╝\e[0m"
echo -e "\e[1mAutomated integration testing script (v$VERSION)\e[0m"
echo
echo "This script will clone, build, configure & run drivechain and sidechain(s)"
echo "The functional unit tests will be run for drivechain and sidechain(s)."
echo "If those tests pass, the integration test script will try to go through"
echo "the process of BMM mining, deposit to and withdraw from the sidechain(s)."
echo
echo "We will also restart the software many times to check for issues with"
echo "shutdown and initialization."
echo
echo -e "\e[1mREAD: YOUR DATA DIRECTORIES WILL BE DELETED\e[0m"
echo
echo "Your data directories ex: ~/.drivechain & ~/.testchain and any other"
echo "sidechain data directories will be deleted!"
echo
echo -e "\e[31mWARNING: THIS WILL DELETE YOUR DRIVECHAIN & SIDECHAIN DATA!\e[0m"
echo
echo -e "\e[32mYou should probably run this in a VM\e[0m"
echo
read -p "Are you sure you want to run this? (yes/no): " WARNING_ANSWER
if [ "$WARNING_ANSWER" != "yes" ]; then
    exit
fi

#
# Functions to help the script
#
function startdrivechain {
    if [ $REINDEX -eq 1 ]; then
        echo
        echo "drivechain will be reindexed"
        echo
        ./mainchain/src/qt/drivechain-qt \
        --reindex \
        --connect=0 \
        --regtest &
    else
        ./mainchain/src/qt/drivechain-qt \
        --connect=0 \
        --regtest &
    fi
}

function starttestchain {
    ./sidechains/src/qt/testchain-qt \
    --connect=0 \
    --regtest \
    --verifybmmacceptheader \
    --verifybmmacceptblock \
    --verifybmmreadblock \
    --verifybmmcheckblock \
    --verifywithdrawalbundleacceptblock \
    --minwithdrawal=1 &
}

function restartdrivechain {
    if [ $SKIP_RESTART -eq 1 ]; then
        return 0
    fi

    #
    # Shutdown drivechain mainchain, restart it, and make sure nothing broke.
    # Exits the script if anything did break.
    #
    # TODO check return value of python json parsing and exit if it failed
    # TODO use jq instead of python
    echo
    echo "We will now restart drivechain & verify its state after restarting!"

    # Record the state before restart
    HASHSCDB=`./mainchain/src/drivechain-cli --regtest gettotalscdbhash`
    HASHSCDB=`echo $HASHSCDB | python -c 'import json, sys; obj=json.load(sys.stdin); print obj["hashscdbtotal"]'`

    # Count doesn't return a json array like the above commands - so no parsing
    COUNT=`./mainchain/src/drivechain-cli --regtest getblockcount`
    # getbestblockhash also doesn't return an array
    BESTBLOCK=`./mainchain/src/drivechain-cli --regtest getbestblockhash`

    # Restart
    ./mainchain/src/drivechain-cli --regtest stop
    sleep 20s # Wait a little bit incase shutdown takes a while
    startdrivechain

    echo
    echo "Waiting for drivechain to start"
    sleep 20s

    # Verify the state after restart
    HASHSCDBRESTART=`./mainchain/src/drivechain-cli --regtest gettotalscdbhash`
    HASHSCDBRESTART=`echo $HASHSCDBRESTART | python -c 'import json, sys; obj=json.load(sys.stdin); print obj["hashscdbtotal"]'`

    COUNTRESTART=`./mainchain/src/drivechain-cli --regtest getblockcount`
    BESTBLOCKRESTART=`./mainchain/src/drivechain-cli --regtest getbestblockhash`

    if [ "$COUNT" != "$COUNTRESTART" ]; then
        echo "Error after restarting drivechain!"
        echo "COUNT != COUNTRESTART"
        echo "$COUNT != $COUNTRESTART"
        exit
    fi
    if [ "$BESTBLOCK" != "$BESTBLOCKRESTART" ]; then
        echo "Error after restarting drivechain!"
        echo "BESTBLOCK != BESTBLOCKRESTART"
        echo "$BESTBLOCK != $BESTBLOCKRESTART"
        exit
    fi

    if [ "$HASHSCDB" != "$HASHSCDBRESTART" ]; then
        echo "Error after restarting drivechain!"
        echo "HASHSCDB != HASHSCDBRESTART"
        echo "$HASHSCDB != $HASHSCDBRESTART"
        exit
    fi

    echo
    echo "drivechain restart and state check check successful!"
    sleep 3s
}

function replacetip {
    if [ $SKIP_REPLACE_TIP -eq 1 ]; then
        return 0
    fi

    # Disconnect chainActive.Tip() and replace it with a new tip

    echo
    echo "We will now disconnect the chain tip and replace it with a new one!"
    sleep 3s

    OLDCOUNT=`./mainchain/src/drivechain-cli --regtest getblockcount`
    OLDTIP=`./mainchain/src/drivechain-cli --regtest getbestblockhash`
    ./mainchain/src/drivechain-cli --regtest invalidateblock $OLDTIP

    sleep 3s # Give some time for the block to be invalidated

    DISCONNECTCOUNT=`./mainchain/src/drivechain-cli --regtest getblockcount`
    if [ "$DISCONNECTCOUNT" == "$OLDCOUNT" ]; then
        echo "Failed to disconnect tip!"
        exit
    fi

    ./mainchain/src/drivechain-cli --regtest generate 1

    NEWTIP=`./mainchain/src/drivechain-cli --regtest getbestblockhash`
    NEWCOUNT=`./mainchain/src/drivechain-cli --regtest getblockcount`
    if [ "$OLDTIP" == "$NEWTIP" ] || [ "$OLDCOUNT" != "$NEWCOUNT" ]; then
        echo "Failed to replace tip!"
        exit
    else
        echo "Tip replaced!"
        echo "Old tip: $OLDTIP"
        echo "New tip: $NEWTIP"
    fi
}

function minemainchain {
    BLOCKS_TO_MINE="$1"

    BLOCKS_MINED=0
    while [ $BLOCKS_MINED -lt $BLOCKS_TO_MINE ]
    do
        OLDCOUNT=`./mainchain/src/drivechain-cli --regtest getblockcount`
        ./mainchain/src/drivechain-cli --regtest generate 1
        NEWCOUNT=`./mainchain/src/drivechain-cli --regtest getblockcount`

        if [ "$OLDCOUNT" -eq "$NEWCOUNT" ]; then
            echo
            echo "Failed to mine mainchain block!"
            exit
        fi

        ((BLOCKS_MINED++))
    done
}

function bmm {
    sleep 1s
    # TODO loop through args to decide which sidechains to bmm

    # Make new bmm request if required and connect new bmm blocks if found
    ./sidechains/src/testchain-cli --regtest refreshbmm $BMM_BID

    sleep 1s

    OLDCOUNT=`./sidechains/src/testchain-cli --regtest getblockcount`

    minemainchain 1

    sleep 1s

    # New sidechain block should be connected
    ./sidechains/src/testchain-cli --regtest refreshbmm $BMM_BID

    NEWCOUNT=`./sidechains/src/testchain-cli --regtest getblockcount`

    if [ "$OLDCOUNT" -eq "$NEWCOUNT" ]; then
        echo
        echo "Failed to BMM!"
        exit
    fi
}








# Remove old data directories
rm -rf ~/.drivechain
rm -rf ~/.testchain








# These can fail, meaning that the repository is already downloaded
if [ $SKIP_CLONE -ne 1 ]; then
    echo
    echo "Cloning repositories"
    git clone https://github.com/drivechain-project/mainchain
    git clone https://github.com/drivechain-project/sidechains
fi








#
# Build repositories & run their unit tests
#
echo
echo "Building repositories"
cd sidechains
if [ $SKIP_BUILD -ne 1 ]; then
    git checkout testchain &&
    git pull &&
    ./autogen.sh

    if [ $INCOMPATIBLE_BDB -ne 1 ]; then
        ./configure
    else
        ./configure --with-incompatible-bdb
    fi

    if [ $? -ne 0 ]; then
        echo "Configure failed!"
        exit
    fi

    make -j "$(nproc)"

    if [ $? -ne 0 ]; then
        echo "Make failed!"
        exit
    fi
fi

if [ $SKIP_CHECK -ne 1 ]; then
    make check
    if [ $? -ne 0 ]; then
        echo "Make check failed!"
        exit
    fi
fi

cd ../mainchain
if [ $SKIP_BUILD -ne 1 ]; then
    git checkout master &&
    git pull &&
    ./autogen.sh

    if [ $INCOMPATIBLE_BDB -ne 1 ]; then
        ./configure
    else
        ./configure --with-incompatible-bdb
    fi

    if [ $? -ne 0 ]; then
        echo "Configure failed!"
        exit
    fi

    make -j "$(nproc)"

    if [ $? -ne 0 ]; then
        echo "Make failed!"
        exit
    fi
fi

if [ $SKIP_CHECK -ne 1 ]; then
    make check
    if [ $? -ne 0 ]; then
        echo "Make check failed!"
        exit
    fi
fi

cd ../




#
# The testing starts here
#




#
# Get mainchain configured and running. Mine first 100 mainchain blocks.
#

# Create configuration file for mainchain
echo
echo "Create drivechain configuration file"
mkdir ~/.drivechain/
touch ~/.drivechain/drivechain.conf
echo "rpcuser=drivechain" > ~/.drivechain/drivechain.conf
echo "rpcpassword=integrationtesting" >> ~/.drivechain/drivechain.conf
echo "server=1" >> ~/.drivechain/drivechain.conf

# Start drivechain-qt
startdrivechain

echo
echo "Waiting for mainchain to start"
sleep 5s

echo
echo "Checking if the mainchain has started"

# Test that mainchain can receive commands and has 0 blocks
GETINFO=`./mainchain/src/drivechain-cli --regtest getmininginfo`
COUNT=`echo $GETINFO | grep -c "\"blocks\": 0"`
if [ "$COUNT" -eq 1 ]; then
    echo
    echo "Drivechain up and running!"
else
    echo
    echo "ERROR failed to send commands to Drivechain or block count non-zero"
    exit
fi

echo
echo "Drivechain will now generate first 100 blocks"
sleep 3s

# Generate 100 mainchain blocks
minemainchain 100

# Check that 100 blocks were mined
GETINFO=`./mainchain/src/drivechain-cli --regtest getmininginfo`
COUNT=`echo $GETINFO | grep -c "\"blocks\": 100"`
if [ "$COUNT" -eq 1 ]; then
    echo
    echo "Drivechain has mined first 100 blocks"
else
    echo
    echo "ERROR failed to mine first 100 blocks!"
    exit
fi

# Disconnect chain tip, replace with a new one
replacetip

# Shutdown drivechain, restart it, and make sure nothing broke
REINDEX=0
restartdrivechain








#
# Activate sidechain testchain
#

# Create a sidechain proposal
./mainchain/src/drivechain-cli --regtest createsidechainproposal 0 "testchain" "testchain for integration test"

# Check that proposal was cached (not in chain yet)
LISTPROPOSALS=`./mainchain/src/drivechain-cli --regtest listsidechainproposals`
COUNT=`echo $LISTPROPOSALS | grep -c "\"title\": \"testchain\""`
if [ "$COUNT" -eq 1 ]; then
    echo
    echo "Sidechain proposal for sidechain testchain has been created!"
else
    echo
    echo "ERROR failed to create testchain sidechain proposal!"
    exit
fi

echo
echo "Will now mine a block so that sidechain proposal is added to the chain"

# Mine one mainchain block, proposal should be in chain after that
minemainchain 1

# Check that we have 101 blocks now
GETINFO=`./mainchain/src/drivechain-cli --regtest getmininginfo`
COUNT=`echo $GETINFO | grep -c "\"blocks\": 101"`
if [ "$COUNT" -eq 1 ]; then
    echo
    echo "mainchain has 101 blocks now"
else
    echo
    echo "ERROR failed to mine block including testchain proposal!"
    exit
fi

# Disconnect chain tip, replace with a new one
replacetip

# Shutdown drivechain, restart it, and make sure nothing broke
REINDEX=0
restartdrivechain

# Check that proposal has been added to the chain and ready for voting
LISTACTIVATION=`./mainchain/src/drivechain-cli --regtest listsidechainactivationstatus`
COUNT=`echo $LISTACTIVATION | grep -c "\"title\": \"testchain\""`
if [ "$COUNT" -eq 1 ]; then
    echo
    echo "Sidechain proposal made it into the chain!"
else
    echo
    echo "ERROR sidechain proposal not in chain!"
    exit
fi
# Check age
COUNT=`echo $LISTACTIVATION | grep -c "\"nage\": 1"`
if [ "$COUNT" -eq 1 ]; then
    echo
    echo "Sidechain proposal age correct!"
else
    echo
    echo "ERROR sidechain proposal age invalid!"
    exit
fi
# Check fail count
COUNT=`echo $LISTACTIVATION | grep -c "\"nfail\": 0"`
if [ "$COUNT" -eq 1 ]; then
    echo
    echo "Sidechain proposal has no failures!"
else
    echo
    echo "ERROR sidechain proposal has failures but should not!"
    exit
fi

# Check that there are currently no active sidechains
LISTACTIVESIDECHAINS=`./mainchain/src/drivechain-cli --regtest listactivesidechains`
if [ "$LISTACTIVESIDECHAINS" == $'[\n]' ]; then
    echo
    echo "Good: no sidechains are active yet"
else
    echo
    echo "ERROR sidechain is already active but should not be!"
    exit
fi

# Shutdown drivechain, restart it, and make sure nothing broke
REINDEX=0
restartdrivechain

echo
echo "Will now mine enough blocks to activate the sidechain"
sleep 5s

# Mine enough blocks to activate the sidechain
minemainchain $SIDECHAIN_ACTIVATION_SCORE

# Check that the sidechain has been activated
LISTACTIVESIDECHAINS=`./mainchain/src/drivechain-cli --regtest listactivesidechains`
COUNT=`echo $LISTACTIVESIDECHAINS | grep -c "\"title\": \"testchain\""`
if [ "$COUNT" -eq 1 ]; then
    echo
    echo "Sidechain has activated!"
else
    echo
    echo "ERROR sidechain failed to activate!"
    exit
fi

echo
echo "listactivesidechains:"
echo
echo "$LISTACTIVESIDECHAINS"

# Disconnect chain tip, replace with a new one
replacetip

# Shutdown drivechain, restart it, and make sure nothing broke
REINDEX=0
restartdrivechain






#
# Get sidechain testchain configured and running
#

# Create configuration file for sidechain testchain
echo
echo "Creating sidechain configuration file"
mkdir ~/.testchain/
touch ~/.testchain/testchain.conf
echo "rpcuser=drivechain" > ~/.testchain/testchain.conf
echo "rpcpassword=integrationtesting" >> ~/.testchain/testchain.conf
echo "server=1" >> ~/.testchain/testchain.conf

echo
echo "The sidechain testchain will now be started"
sleep 5s

# Start the sidechain and test that it can receive commands and has 0 blocks
starttestchain

echo
echo "Waiting for testchain to start"
sleep 5s

echo
echo "Checking if the sidechain has started"

# Test that sidechain can receive commands and has 0 blocks
GETINFO=`./sidechains/src/testchain-cli --regtest getmininginfo`
COUNT=`echo $GETINFO | grep -c "\"blocks\": 0"`
if [ "$COUNT" -eq 1 ]; then
    echo "Sidechain up and running!"
else
    echo "ERROR failed to send commands to sidechain"
    exit
fi

# Check if the sidechain can communicate with the mainchain








#
# Start BMM mining the sidechain
#

# The first time that we call this it should create the first BMM request and
# send it to the mainchain node, which will add it to the mempool
echo
echo "Going to refresh BMM on the sidechain and send BMM request to mainchain"
./sidechains/src/testchain-cli --regtest refreshbmm $BMM_BID

# TODO check that mainchain has BMM request in mempool

echo
echo "Giving mainchain some time to receive BMM request from sidechain..."
sleep 3s

echo
echo "Mining block on the mainchain, should include BMM commit"

# Mine a mainchain block, which should include the BMM request we just made
minemainchain 1

sleep 2s

# Shutdown drivechain, restart it, and make sure nothing broke
REINDEX=1
restartdrivechain

# TODO verifiy that bmm request was added to chain and removed from mempool

# Refresh BMM again, this time the block we created the first BMM request for
# should be added to the side chain, and a new BMM request created for the next
# block
echo
echo "Will now refresh BMM on the sidechain again and look for our BMM commit"
echo "BMM block will be connected to the sidechain if BMM commit was made."
./sidechains/src/testchain-cli --regtest refreshbmm $BMM_BID

# Check that BMM block was added to the sidechain
GETINFO=`./sidechains/src/testchain-cli --regtest getmininginfo`
COUNT=`echo $GETINFO | grep -c "\"blocks\": 1"`
if [ "$COUNT" -eq 1 ]; then
    echo "Sidechain connected BMM block!"
else
    echo "ERROR sidechain has no BMM block connected!"
    exit
fi

# Mine some more BMM blocks
echo
echo "Now we will test mining more BMM blocks"

for ((i = 0; i < 10; i++)); do
    echo "Mining BMM!"
    bmm
done

# Shutdown drivechain, restart it, and make sure nothing broke
REINDEX=0
restartdrivechain





#
# Deposit to the sidechain
#

echo "We will now deposit to the sidechain"
sleep 3s

# Create sidechain deposit
ADDRESS=`./sidechains/src/testchain-cli --regtest getnewaddress sidechain legacy`
DEPOSITADDRESS=`./sidechains/src/testchain-cli --regtest formatdepositaddress $ADDRESS`
./mainchain/src/drivechain-cli --regtest createsidechaindeposit 0 $DEPOSITADDRESS 1 0.01

# Verify that there are currently no deposits in the db
DEPOSITCOUNT=`./mainchain/src/drivechain-cli --regtest countsidechaindeposits 0`
if [ $DEPOSITCOUNT -ne 0 ]; then
    echo "Error: There is already a deposit in the db when there should be 0!"
    exit
else
    echo "Good: No deposits in db yet"
fi

# Generate a block to add the deposit to the mainchain
./mainchain/src/drivechain-cli --regtest generate 1
CURRENT_BLOCKS=$(( CURRENT_BLOCKS + 1 )) # TODO stop using CURRENT_BLOCKS

# Verify that a deposit was added to the db
DEPOSITCOUNT=`./mainchain/src/drivechain-cli --regtest countsidechaindeposits 0`
if [ $DEPOSITCOUNT -ne 1 ]; then
    echo "Error: No deposit was added to the db!"
    exit
else
    echo "Good: Deposit added to db"
fi

# Replace the chain tip and restart
replacetip
REINDEX=0
restartdrivechain

# Verify that a deposit is still in the db after replacing tip & restarting
DEPOSITCOUNT=`./mainchain/src/drivechain-cli --regtest countsidechaindeposits 0`
if [ $DEPOSITCOUNT -ne 1 ]; then
    echo "Error: Deposit vanished after replacing tip & restarting!"
    exit
else
    echo "Good: Deposit still in db after replacing tip & restarting"
fi

# Mine some blocks and BMM the sidechain so it can process the deposit
for ((i = 0; i < 10; i++)); do
    echo "Mining BMM!"
    bmm
done

# Check if the deposit address has any transactions on the sidechain
LIST_TRANSACTIONS=`./sidechains/src/testchain-cli --regtest listtransactions "sidechain"`
COUNT=`echo $LIST_TRANSACTIONS | grep -c "\"address\": \"$ADDRESS\""`
if [ "$COUNT" -ge 1 ]; then
    echo
    echo "Sidechain deposit address has transactions!"
else
    echo
    echo "ERROR sidechain did not receive deposit!"
    exit
fi

# Check for the deposit amount
COUNT=`echo $LIST_TRANSACTIONS | grep -c "\"amount\": 0.99999000"`
if [ "$COUNT" -eq 1 ]; then
    echo
    echo "Sidechain received correct deposit amount!"
else
    echo
    echo "ERROR sidechain did not receive deposit!"
    exit
fi

# Shutdown drivechain, restart it, and make sure nothing broke
REINDEX=0
restartdrivechain

echo
echo "Now we will BMM the sidechain to confirm the deposit!"

# Sleep here so user can read the deposit debug output
sleep 5s

# Mature the deposit on the sidechain, so that it can be withdrawn
for ((i = 0; i < 6; i++)); do
    echo "Mining BMM!"
    bmm
done

# Check that the deposit has been added to our sidechain balance
BALANCE=`./sidechains/src/testchain-cli --regtest getbalance`
BC=`echo "$BALANCE>0.9" | bc`
if [ $BC -eq 1 ]; then
    echo
    echo "Sidechain balance updated, deposit matured!"
    echo "Sidechain balance: $BALANCE"
else
    echo
    echo "ERROR sidechain balance not what it should be... Balance: $BALANCE!"
    exit
fi


# Test sending the deposit around to other addresses on the sidechain
# TODO




# Shutdown drivechain, restart it, and make sure nothing broke
REINDEX=1
restartdrivechain




#
# Withdraw from the sidechain
#

# Get a mainchain address and testchain refund address
MAINCHAIN_ADDRESS=`./mainchain/src/drivechain-cli --regtest getnewaddress mainchain legacy`
REFUND_ADDRESS=`./sidechains/src/testchain-cli --regtest getnewaddress refund legacy`

# Call the CreateWithdrawal RPC
echo
echo "We will now create a withdrawal on the sidechain"
./sidechains/src/testchain-cli --regtest createwithdrawal $MAINCHAIN_ADDRESS $REFUND_ADDRESS 0.5 0.1 0.1
sleep 3s

# Mine enough BMM blocks for a withdrawal bundle to be created and sent to the
# mainchain. We will mine up to 300 blocks before giving up.
echo
echo "Now we will mine enough BMM blocks for the sidechain to create a bundle"
for ((i = 0; i < 300; i++)); do
    bmm

    # Check for bundle
    BUNDLECHECK=`./mainchain/src/drivechain-cli --regtest listwithdrawalstatus 0`
    if [ "-$BUNDLECHECK-" != "--" ]; then
        echo "Bundle has been found!"
        break
    fi
done

# Check if bundle was created
HASHBUNDLE=`./mainchain/src/drivechain-cli --regtest listwithdrawalstatus 0`
HASHBUNDLE=`echo $HASHBUNDLE | python -c 'import json, sys; obj=json.load(sys.stdin); print obj[0]["hash"]'`
if [ -z "$HASHBUNDLE" ]; then
    echo "Error: No withdrawal bundle found"
    exit
else
    echo "Good: bundle found: $HASHBUNDLE"
fi

# Check that bundle has work score
WORKSCORE=`./mainchain/src/drivechain-cli --regtest getworkscore 0 $HASHBUNDLE`
if [ $WORKSCORE -lt 1 ]; then
    echo "Error: No Workscore!"
    exit
else
    echo "Good: workscore: $WORKSCORE"
fi

# Check that if we replace the tip the workscore does not change
replacetip
NEWWORKSCORE=`./mainchain/src/drivechain-cli --regtest getworkscore 0 $HASHBUNDLE`
if [ $NEWWORKSCORE -ne $WORKSCORE ]; then
    echo "Error: Workscore invalid after replacing tip!"
    echo "$NEWWORKSCORE != $WORKSCORE"
    exit
else
    echo "Good - Workscore: $NEWWORKSCORE unchanged"
fi

# Set our node to upvote the withdrawal
echo "Setting vote for withdrawal to upvote!"
sleep 5s
./mainchain/src/drivechain-cli --regtest setwithdrawalvote upvote 0 $HASHBUNDLE

# Mine blocks until payout should happen
BLOCKSREMAINING=`./mainchain/src/drivechain-cli --regtest listwithdrawalstatus 0`
BLOCKSREMAINING=`echo $BLOCKSREMAINING | python -c 'import json, sys; obj=json.load(sys.stdin); print obj[0]["nblocksleft"]'`
WORKSCORE=`./mainchain/src/drivechain-cli --regtest getworkscore 0 $HASHBUNDLE`

echo
echo "Blocks remaining in verification period: $BLOCKSREMAINING"
echo "Workscore: $WORKSCORE / $MIN_WORK_SCORE"
sleep 10s

echo "Will now mine $MIN_WORK_SCORE blocks"
./mainchain/src/drivechain-cli --regtest generate $MIN_WORK_SCORE


# Check if balance of  address received payout
WITHDRAW_BALANCE=`./mainchain/src/drivechain-cli --regtest getbalance mainchain`
BC=`echo "$WITHDRAW_BALANCE>0.4" | bc`
if [ $BC -eq 1 ]; then
    echo
    echo
    echo -e "\e[32m==========================\e[0m"
    echo
    echo -e "\e[1mpayout received!\e[0m"
    echo "amount: $WITHDRAW_BALANCE"
    echo
    echo -e "\e[32m==========================\e[0m"
else
    echo
    echo -e "\e[31mError: payout not received!\e[0m"
    exit
fi

# Shutdown drivechain, restart it, and make sure nothing broke
REINDEX=0
restartdrivechain

# Restart again but with reindex
REINDEX=1
restartdrivechain

# Mine 100 more mainchain blocks
minemainchain 100

echo
echo
echo -e "\e[32mdrivechain integration testing completed!\e[0m"
echo
echo "Make sure to backup log files you want to keep before running again!"
echo
echo -e "\e[32mIf you made it here that means everything probably worked!\e[0m"
echo "If you notice any issues but the script still made it to the end, please"
echo "open an issue on GitHub!"

if [ $SKIP_SHUTDOWN -ne 1 ]; then
    # Stop the binaries
    echo
    echo
    echo "Will now shut down!"
    ./mainchain/src/drivechain-cli --regtest stop
    ./sidechains/src/testchain-cli --regtest stop
fi

