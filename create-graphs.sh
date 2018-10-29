#!/bin/bash

for repo in $(cat test-repos.txt)
do
	(
		echo $repo
		cd $repo
		../git/git commit-graph write --reachable --version=0	
		cp .git/objects/info/commit-graph .git/objects/info/commit-graph.0
	
		for v in 1 2 3 4
		do
			cp .git/objects/info/commit-graph.0 .git/objects/info/commit-graph
			../git/git commit-graph write --reachable --version=$v
			cp .git/objects/info/commit-graph .git/objects/info/commit-graph.$v
		done
	)
done

