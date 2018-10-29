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
	./test-order-tests.sh >topo-order-summary.txt
)
