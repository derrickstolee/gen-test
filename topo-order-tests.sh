#!/bin/bash

TESTDIR=~/gen-tests

for repo in $(cat $TESTDIR/test-repos.txt)
do
	echo $repo
	cd ~/$repo

	for v in 0 1 2 3 4 
	do
		cp .git/objects/info/commit-graph.$v .git/objects/info/commit-graph

		for n in 100 1000 10000
		do
			LOGFILE=$TESTDIR/log-$repo-$n-$v.txt
			rm -f $LOGFILE

			GIT_TR2_PERFORMANCE=$LOGFILE ~/git/git log --topo-order -$n >/dev/null

			echo "$repo	$n	$v	$(grep "key:num_walked_explore" $LOGFILE \
				| sed "s/:/ /g" \
				| grep -oE '[^ ]+$')"
		done
	done

done
