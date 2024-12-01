#!/bin/bash

# exit on error
set -e

# Run forge coverage
forge coverage \
    --report lcov \
    --report summary \
    --no-match-coverage "(test|mock|script)" 

# Install lcov
brew install lcov

# Generate HTML report from lcov.info
genhtml lcov.info -o coverage --branch-coverage --ignore-errors inconsistent,category,corrupt