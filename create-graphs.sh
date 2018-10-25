#!/bin/bash

for v in 0 1 2 3 4
do
	cp .git/objects/info/commit-graph.0 .git/objects/info/commit-graph
	~/git/git commit-graph write --reachable --version=$v
	cp .git/objects/info/commit-graph .git/objects/info/commit-graph.$v
done

