#!/bin/bash

set -uoe pipefail

usage() {
    echo "Add delegations in the genesis file from a CSV file."
    echo "The genesis from FETCHD_HOME (default: ~/.fetchd/) will be updated."
    echo -e "\nUsage:\n    $0 [csv_file]\n" 
    echo -e "Env:"
    echo -e "    FETCHD_HOME: specify the location of the fetchd home folder\n"
    exit 1
}

# some systems default to mawk, which can't do 64bits maths, so make sure gawk is here.
which gawk >/dev/null 2>&1 || (echo "gawk is required and not installed. Install it with 'sudo apt-get install gawk'" && exit 1)

FETCHD_HOME="${FETCHD_HOME:=~/.fetchd/}"
# Validators that will receive delegations, in a round-robin fashion
TARGET_VALIDATORS=(
"fetchvaloper15x27jkea0h9gz5jdegu39j3393aqvrkdhg7r3v"
"fetchvaloper1qypf5ulfttynmt25wcvrh7zl7nwzgpg9kwsr4e"
"fetchvaloper1gdpc66xnunmsgpf0s7qe26sxl7dp3meky3kerd"
"fetchvaloper1gqj3wjn7dds043npes6yndt9vymqs5zyz6qck6"
)
BOND_DENOM="atestfet"
# minimum amount required to create a delegation, below, no delegation is 
# created and everything is transferred on the user account
# value is in units of BOND_DENOM
MIN_DELEGATED_AMOUNT="2000000000000000000"
# amount subtracted from the delegated amount and transferred 
# on the user account when a delegation is created 
# value is in units of BOND_DENOM
ACCOUNT_RESERVED_AMOUNT="1000000000000000000"
# Number of expected fields per line in the CSV file
EXPECTED_NUMFIELDS="6"

if [ $# -ne 1 ]; then
    usage
    exit 1
fi

CSV_FILE="$1"

if [ ! -f "${CSV_FILE}" ]; then
    usage
    exit 1
fi

NUMFIELDS=$(head -n1 "${CSV_FILE}" | gawk -F',' '{print NF}')
if [ "${NUMFIELDS}" -ne "${EXPECTED_NUMFIELDS}" ]; then 
    echo "invalid CSV file, expected ${EXPECTED_NUMFIELDS}, got ${NUMFIELDS}"
    exit 1
fi

FETCHD_HOME=$(realpath "${FETCHD_HOME}")
GENESIS_FILE="${FETCHD_HOME}/config/genesis.json"
if [ ! -f "${GENESIS_FILE}" ]; then
    echo "Cannot read genesis.json from ${FETCHD_HOME}"
    exit 1
fi

ORIGINAL_GENESIS="${GENESIS_FILE}.orig"
# Backup current genesis. In case of errors while adding delegations,
# genesis file will be reverted to pristine state.
cp -f "${GENESIS_FILE}" "${ORIGINAL_GENESIS}"

restore () {
    echo "An error occured, reverting the genesis.json to previous state"
    cp -f "${ORIGINAL_GENESIS}" "${GENESIS_FILE}"
}
cleanup () {
    rm "${ORIGINAL_GENESIS}"
}

trap restore ERR
trap cleanup EXIT

COUNTER=0
while read -r line; do
    FETCH_ADDR=$(echo "${line}" | gawk -F',' '{print $3}')
    VALIDATOR=${TARGET_VALIDATORS[$((COUNTER % ${#TARGET_VALIDATORS[@]}))]}
    AMOUNT=$(echo "${line}" | gawk -F',' '{print $4}')
    fetchd add-genesis-delegation \
        --home "${FETCHD_HOME}" \
        --account-reserved-amount "${ACCOUNT_RESERVED_AMOUNT}${BOND_DENOM}" \
        --min-delegated-amount "${MIN_DELEGATED_AMOUNT}${BOND_DENOM}" \
        "${FETCH_ADDR}" "${VALIDATOR}" "${AMOUNT}${BOND_DENOM}" 
    if [[ `echo "${AMOUNT} ${MIN_DELEGATED_AMOUNT}" | gawk '{print ($1 >= $2)}'` == 1 ]]; then
        echo "Added ${ACCOUNT_RESERVED_AMOUNT}${BOND_DENOM} to ${FETCH_ADDR}"
        echo "Delegated $(echo "${AMOUNT} ${ACCOUNT_RESERVED_AMOUNT}" | gawk '{printf "%.0f", $1-$2}')${BOND_DENOM} from ${FETCH_ADDR} to ${VALIDATOR}"
        COUNTER=$((COUNTER + 1))
    else
        echo "Added ${AMOUNT%.*}${BOND_DENOM} to ${FETCH_ADDR}"
    fi
done <<<"$(LC_ALL=C sort "${CSV_FILE}")"
