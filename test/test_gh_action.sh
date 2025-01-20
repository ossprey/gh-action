#!/bin/bash


cd /workspaces/gh-action/
docker build -t ossprey-scan .

export INPUT_PACKAGE="test/simple_math"
export INPUT_REQUIREMENTS=true
export INPUT_PIPENV=false
export INPUT_VERBOSE=true
export INPUT_DRY_RUN=false

/usr/bin/docker run --label 2a0600 --workdir /github/workspace --rm -e "pythonLocation" -e "LD_LIBRARY_PATH"  \
         -e "API_KEY=$OSSPREY_API_KEY" -e "INPUT_PACKAGE" -e "INPUT_REQUIREMENTS" -e "INPUT_GITHUB_COMMENTS" -e "INPUT_VERBOSE" \
         -e "INPUT_PIPENV" -e "INPUT_URL" -e "INPUT_DRY_RUN" -e "HOME" \
         -v "/var/run/docker.sock":"/var/run/docker.sock" -v "/workspaces/gh-action/":"/github/workspace" \
         ossprey-scan
cd -