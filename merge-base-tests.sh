#!/bin/bash

TESTDIR=$(pwd)

while read -r repo mergeA mergeB
do
	echo $repo $mergeA $mergeB

	cd $TESTDIR/$repo

	cp .git/objects/info/commit-graph.0 .git/objects/info/commit-graph

	LOGFILE=$TESTDIR/merge-$repo-OLD.txt
	rm -f $LOGFILE

	GIT_TEST_OLD_PAINT=1 GIT_TR2_PERFORMANCE=$LOGFILE $TESTDIR/git/git merge-base $mergeA $mergeB >/dev/null

	echo "$repo	$mergeA	$mergeB	OLD	$(grep "key:num_walked" $LOGFILE \
		| sed "s/:/ /g" \
		| grep -oE '[^ ]+$')"

	for v in 0 1 2 3 4 
	do
		cp .git/objects/info/commit-graph.$v .git/objects/info/commit-graph

		LOGFILE=$TESTDIR/merge-$repo-$v.txt
		rm -f $LOGFILE

		GIT_TR2_PERFORMANCE=$LOGFILE $TESTDIR/git/git merge-base $mergeA $mergeB >/dev/null

		echo "$repo	$mergeA	$mergeB	$v	$(grep "key:num_walked" $LOGFILE \
			| sed "s/:/ /g" \
			| grep -oE '[^ ]+$')"
	done

done <$TESTDIR/test-merges.txt
