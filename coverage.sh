#!/bin/bash

# exit on error
set -e

# give error if `lcov` is not installed
if ! command -v lcov &> /dev/null
then
    echo "lcov could not be found. Please install lcov"
    exit
fi

# give error if `genhtml` is not installed
if ! command -v genhtml &> /dev/null
then
    echo "genhtml could not be found. Please install lcov"
    exit
fi

# generate coverage info
forge coverage \
    --report lcov \
    --report summary \
    --no-match-coverage "(test|mock|script)" 

# generate HTML report from lcov.info
genhtml lcov.info -o coverage --branch-coverage --ignore-errors inconsistent,category,corrupt

# open report
open coverage/index.html
