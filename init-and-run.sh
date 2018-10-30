#!/bin/bash

./clone-repos.sh

(
	cd git
	make -j12 DEVELOPER=1
)

(
	./create-graphs.sh
)

(
	./test-merges.sh >test-merges-summary.txt
)

(
	./topo-order-tests.sh >topo-order-summary.txt
)

(
	./topo-compare-tests.sh >topo-compare-summary.txt
)
