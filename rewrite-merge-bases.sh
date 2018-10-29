#!/bin/bash

TESTDIR=$(pwd)

while read -r repo mergeA mergeB
do

	cd $TESTDIR/$repo

	echo $repo $(git rev-parse --short $mergeA^{commit}) $(git rev-parse --short $mergeB^{commit})

done <$TESTDIR/test-merges.txt
