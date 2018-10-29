Generation Number Performance Test
==================================

Git uses the commit history to answer many basic questions, such as
computing a merge-base. Some of these algorithms can benefit from a
_reachability index_, which is a condition that allows us to answer
"commit A cannot reach commit B" in some cases. These require pre-
computing some values that we can load and use at run-time. Git
already has a notion of _generation number_, stores it in the commit-
graph file, and uses it in several reachability algorithms.

You can read more about generation numbers and how to use them in
algorithms in [this blog post](https://blogs.msdn.microsoft.com/devops/2018/07/09/supercharging-the-git-commit-graph-iii-generations/).

However, [generation numbers do not always improve our algorithms](https://public-inbox.org/git/pull.28.git.gitgitgadget@gmail.com/T/#u).
Specifically, some algorithms in Git already use commit date as a
heuristic reachability index. This has some problems, though, since
commit date can be incorrect for several reasons (clock skew between
machines, purposefully setting GIT_COMMIT_DATE to the author date, etc.).
However, the speed boost by using commit date as a cutoff was so
important in these cases, that the potential for incorrect answers was
considered acceptable.

When these algorithms were converted to use generation numbers, we
_added_ the extra constraint that the algorithms are _never incorrect_.
Unfortunately, this led to some cases where performance was worse than
before. There are known cases where `git merge-base A B` or
`git log --topo-order A..B` are worse when using generation numbers
than when using commit dates.

This report investigates four replacements for generation numbers, and
compares the number of walked commits to the existing algorithms (both
using generation numbers and not using them at all). We can use this
data to make decisions for the future of the feature.

### Implementation

The reachability indexes below are implemented in
[the `reach-perf` branch in https://github.com/derrickstolee/git](https://github.com/derrickstolee/git/tree/reach-perf).
This implementation is in a very rough condition, as it is intended to
be a prototype, not production-quality.

Using this implementation, you can compute commit-graph files for the
specified reachability index using `git commit-graph write --reachable --version=<V>`.
The `git` client will read the version from the file, so our tests
store each version as `.git/objects/info/commit-graph.<V>` and copy
the necessary file to `.git/objects/info/commit-graph` before testing.

The algorithms count the number of commits walked, as to avoid the
noise that would occur with time-based performance reporting. We use
the (in progress) trace2 library for this. To find the values reported,
use the `GIT_TR2_PERFORMANCE` environment variable.

To ignore reachability indexes entirely and use the old algorithms
(reported here as "OLD" values) use the environment variable
`GIT_TEST_OLD_PAINT=1`.


Reachability Index Versions
---------------------------

**V0: (Minimum) Generation Number.**
The _generation number_ of a commit is exactly one more than the maximum
generation number of a parent (by convention, the generation number of a
commit with no parents is 1). This is the definition currently used by
Git (2.19.0 and later). Given two commits A and B, we can then use the
following reachability index:

    If gen(A) < gen(B), then A cannot reach B.

_Commentary:_ One issue with generation numbers is that some algorithms
in Git use commit date as a heuristic, and allow incorrect answers if
there is enough clock skew. Using that heuristic, the algorithms can walk
fewer commits than the algorithms using generation number. The other
reachability indexes introduced below attempt to fix this problem.

**V1: (Epoch, Date) Pairs.**
For each commit, store a pair of values called the _epoch_ and the _date_.
The date is the normal commit date. The _epoch_ of a commit is the minimum
X such that X is at least the maximum epoch of each parent, and at least
one more than the epoch of any parent whose date is larger than the date
of this commit (i.e. there is clock skew between this commit and this
parent). In this way, we can use the following reachability index:

   If epoch(A) < epoch(B), then A cannot reach B.
   If epoch(A) == epoch(B) and date(A) < date(B), then A cannot reach B.

**V2: Maximum Generation Numbers.**
The _maximum generation number_ of a commit (denoted by maxgen(A)) is
defined using its _children_ and the total number of commits in the repo.
If A is a commit with no children (that is, there is no commit B with
A as a parent) then maxgen(A) is equal to the number of commits in the repo.
For all other commits A, maxgen(A) is one less than the minimum maxgen(B)
among children B. This can be computed by initializing maxgen(C) to the
number of commits, then walking the commit graph in topological order,
assigning maxgen(P) = min { maxgen(P), maxgen(C) - 1 } for each parent P
of the currently-walking commit C. We then have the same reachability
index as minimum generation number:

  If maxgen(A) < maxgen(B), then A cannot reach B.

_Commentary:_ The known examples where (minimum) generation numbers perform
worse than commit date heuristics involve commits with recent commit dates
but whose parents have very low generation number compared to most recent
commits. In a way, minimum generation numbers increase the odds that we
can say "A cannot reach B" when A is fixed and B is selected at random.
Maximum generation numbers increase the odds that we can say "A cannot
reach B" when B is fixed and A is selected at random. This helps us when
we are exploring during a reachability algorithm and have explored few
commits and want to say that the large set of unexplored commits cannot
reach any of the explored commits.

**V3: Corrected Commit Date.**
For a commit C, let its _corrected commit date_ (denoted by cdate(C))
be the maximum of the commit date of C and the commit dates of its
parents.

  If cdate(A) < cdate(B), then A cannot reach B.

**V4: FELINE Index.**
The FELINE index is a two-dimentional reachability index as defined in
[Reachability Queries in Very Large Graphs: A Fast Refined Online Search Approach](https://openproceedings.org/EDBT/2014/paper_166.pdf)
by Veloso, Cerf, Jeira, and Zaki. The index is not deterministically
defined, but instead is defined in the following way:

1. Compute a reverse topological order of the commits. Let felineX(C)
   be the position in which C appears in this list. Since this is
   a reverse topological order, felineX(C) > felineX(P) for each parent
   P of C.

2. Compute a reverse topological order of the commits using Kahn's
   algorithm, but when selecting among a list of commits with in-degree
   zero, prioritize the commit by minimizing felineX. Let felineY(C)
   be the position in which C appears in this list.

Essentially, the felineY order is selected with the goal of swapping
positions of topologically-independent commits relative to the felinX
ordering. The resulting reachability index is as follows:

   If felineX(A) < felineY(B), then A cannot reach B.
   If felineY(A) < felineY(B), then A cannot reach B.

_Commentary:_ In terms of comparing two commits directly, this index
is quite strong. However, when we are performing our reachability
algorithms that care about reachable sets (git log --graph), or
boundaries between reachable sets (git merge-base, git log --graph A..B)
we need to track a single pair (minX,minY) for comparion. In order to not
miss anything during our search, we need to update this pair to be
the minimum felineX(A) and minimum felineY(B) among all explored commits
A and B. That is, the pair (minX, minY) is below our entire explored set.
This can be a disadvantage for these algorithms.

### Comparing Reachability Index Versions Viability

Before considering how well these indexes perform during our algorithm
runs, let's take a moment to consider the implementation details and
how they relate to the existing commit-graph file format and existing
Git clients.

* **Compatible?** In our test implementation, we use a previously unused
  byte of data in the commit-graph format to indicate which reachability
  index version we are using. Existing clients ignore this value, so we
  will want to consider if these new indexes are _backwards compatible_.
  That is, will they still report correct values if they ignore this byte
  and use the generation number column from the commit-graph file assuming
  the values are minimum generation numbers?

* **Immutable?** Git objects are _immutable_. If you change an object you
  actually create a new object with a new object ID. Are the values we store
  for these reachability indexes also immutable?

* **Local?** Are these values **locally computable**? That is, do we only
  need to look at the parents of a commit (assuming those parents have
  computed values) in order to determine the value at that commit?

| Index                     | Compatible? | Immutable? | Local? |
|---------------------------|-------------|------------|--------|
| Minimum Generation Number | Yes         | Yes        | Yes    |
| (Epoch, Date) pairs       | Yes         | Yes        | Yes    |
| Maximum Generation Number | Yes         | No         | No     |
| Corrected Commit Date     | No          | Yes        | Yes    |
| FELINE index              | Yes         | No         | No     |

_Note:_ The corrected commit date uses the generation number column
to store an offset of "how much do I need to add to my commit date
to get my corrected commit date?" The values stored in that column
are then not backwards-compatible.

_Note:_ The FELINE index requires storing two values instead of just
one. One of these values could be stored in the generation number
column and the other in an optional chunk, hence it could be backwards
compatible. (This is not how it is implemented in our example
implementation.)


Data
----

We focused on three types of performance tests that test the indexes
in different ways. Each test lists the `git` command that is used,
and the table lists which repository is used and which inputs.

### Test 1: `git log --topo-order -N`

This test focuses on the number of commits that are parsed during
a `git log --topo-order` before writing `N` commits to output.

You can reproduce this test using `topo-order-tests.sh` and
see all the data in `topo-order-summary.txt`. The values reported
here are a sampling of the data, ignoring tests where all values
were the same or extremely close in value.


| Repo         | N     | V0     | V1     | V2     | V3     | V4    |
|--------------|-------|--------|--------|--------|--------|-------|
| android-base | 100   |  5,487 |  8,534 |  6,937 |  6,419 | 6,453 |
| android-base | 1000  | 36,029 | 44,030 | 41,493 | 41,206 |45,431 |
| chromium     | 100   |    101 |424,406 |    101 |    101 |   101 |
| gerrit       | 100   |  8,212 |  8,533 |    164 |    159 |   162 |
| gerrit       | 1000  |  8,512 |  8,533 |  1,990 |  1,973 | 3,766 |
| Linux        | 100   | 12,458 | 12,444 | 13,683 | 13,123 |13,124 |
| Linux        | 1000  | 24,436 | 26,247 | 27,878 | 26,430 |27,875 |
| Linux        | 10000 | 30,364 | 28,891 | 27,878 | 26,430 |27,875 |
| electron     | 1000  | 19,927 | 18,733 |  1,072 | 18,214 |18,214 |
| Ffmpeg       | 10000 | 32,154 | 47,429 | 10,435 | 11,054 |11,054 |
| jgit         | 1000  |  1,550 |  6,264 |  1,067 |  1,060 | 1,233 |
| julia        | 10000 | 43,043 | 43,043 | 10,201 | 23,505 |23,828 |
| odoo         | 1000  | 17,175 |  9,714 |  4,043 |  4,046 | 4,111 |
| php-src      | 1000  | 19,014 | 27,530 |  1,311 |  1,305 | 1,320 |
| rails        | 100   |  1,420 |  2,041 |  1,757 |  1,428 | 1,441 |
| rails        | 1000  |  7,952 | 10,145 | 10,053 |  8,373 | 8,373 |
| swift        | 1000  |  1,914 |  4,004 |  2,071 |  1,939 | 1,940 |
| tensorflow   | 1000  | 10,019 | 39,221 |  6,711 | 10,051 |10,051 |
| TypeScript   | 1000  |  2,873 | 12,014 |  3,049 |  2,876 | 2,876 |


### Test 2: `git log --topo-order -10 A..B`

This test focuses on the number of commits that are parsed during
a `git log --topo-order A..B` before writing ten commits to output.
Since we fix a very small set of output commits, we care more about
the part of the walk that determines which commits are reachable
from `B` but not reachable from `A`. This part of the walk uses
commit date as a heuristic in the existing implementation.

You can reproduce this test using `topo-compare-tests.sh` and
see all the data in `topo-compare-summary.txt`. The values reported
here are a sampling of the data, ignoring tests where all values
were the same or extremely close in value.

_Note:_ For some of the rows, the `A` and `B` values may be
swapped from what is expected. This is due to (1) a bug in the
reference implementation that doesn't short-circuit the walk
when `A` can reach `B`, and (2) data-entry errors by the author.
The bug can be fixed, but would have introduced strange-looking
rows in this table.

| Repo         | A            | B            | OLD     | V0     | V1     | V2     | V3      | V4     |
|--------------|--------------|--------------|---------|--------|--------|--------|---------|--------|
| android-base | 53c1972bc8f  | 92f18ac3e39  |  39,403 |  1,544 |  6,957 |     26 |   1,015 |  1,098 |
| gerrit       | c4311f7642   | 777a8cd1e0   |   6,457 |  7,836 | 10,869 |    415 |     414 |    445 |
| electron     | 7da7dd85e    | addf069f2    |  18,164 |    945 |  6,528 |     17 |      17 |     18 |
| julia        | 7faee1b201   | e2022b9f0f   |  22,800 |  4,221 | 12,710 |    377 |     213 |    213 |
| julia        | ae69259cd9   | c8b5402afc   |   1,864 |  1,859 | 13,287 |     12 |   1,859 |  1,859 |
| Linux        | 69973b830859 | c470abd4fde4 | 111,692 | 77,263 | 96,598 | 80,238 |  76,332 | 76,495 |
| Linux        | c3b92c878736 | 19f949f52599 | 167,418 |  5,736 |  4,684 |  9,675 |   3,887 |  3,923 |
| Linux        | c8d2bc9bc39e | 69973b830859 |  44,940 |  4,056 | 16,636 | 10,405 |   3,475 |  4,022 |
| odoo         | 4a31f55d0a0  | 93fb2b4a616  |  25,139 | 19,528 | 20,418 | 19,874 |  19,634 | 27,247 |
| swift        | 4046359efd   | b34b6a14c7   |  13,411 |    662 |    321 |     12 |      80 |    134 |
| tensorflow   | ec6d17219c   | fa1db5eb0d   |  10,373 |  4,762 | 36,272 |    174 |   3,631 |  3,632 |
| TypeScript   | 35ea2bea76   | 123edced90   |   3,450 |    267 | 10,386 |     27 |     259 |    259 |


### Test 3: `git merge-base A B`

This test focuses on the number of commits that are parsed during
a `git merge-base A B`. This part of the walk uses commit date as
a heuristic in the existing implementation.

You can reproduce this test using `merge-base-tests.sh` and
see all the data in `merge-base-summary.txt`. The values reported
here are a sampling of the data, ignoring tests where all values
were the same or extremely close in value.


| Repo         | A            | B            | OLD     | V0      | V1      | V2      | V3      | V4      |
|--------------|--------------|--------------|---------|---------|---------|---------|---------|---------|
| android-base | 53c1972bc8f  | 92f18ac3e39  |  81,999 | 109,025 |  81,885 |  77,475 |  81,999 |  82,001 |
| gerrit       | c4311f7642   | 777a8cd1e0   |   6,468 |   7,995 |   6,566 |   6,478 |   6,468 |   6,468 |
| electron     | 7da7dd85e    | addf069f2    |  18,160 |  19,871 |  18,670 |   2,231 |  18,160 |  18,160 |
| julia        | 7faee1b201   | e2022b9f0f   |  22,803 |  42,339 |  42,212 |   6,803 |  22,803 |  22,803 |
| julia        | c8b5402afc   | ae69259cd9   |   7,076 |  42,909 |  42,770 |   2,690 |   7,076 |   7,076 |
| Linux        | 69973b830859 | c470abd4fde4 |  44,984 |  47,457 |  44,679 |  38,461 |  44,984 |  44,984 |
| Linux        | c3b92c878736 | 19f949f52599 | 111,740 | 111,027 | 111,196 | 107,835 | 111,771 | 111,368 |
| Linux        | c8d2bc9bc39e | 69973b830859 | 167,468 | 635,579 | 630,138 |  33,716 | 167,496 | 153,774 |
| odoo         | 4a31f55d0a0  | 93fb2b4a616  |  25,150 |  27,259 |  23,977 |  24,041 |  23,974 |  26,829 |
| swift        | 4046359efd   | b34b6a14c7   |  13,434 |  13,254 |  13,940 |  16,023 |  13,127 |  15,008 |
| tensorflow   | ec6d17219c   | fa1db5eb0d   |  10,377 |  10,448 |  10,377 |   8,460 |  10,377 |  10,377 |
| TypeScript   | 35ea2bea76   | 123edced90   |   3,464 |   3,439 |   3,464 |   3,581 |   3,464 |   3,464 |


Conclusions
-----------

Based on the performance results alone, we should remove minimum
generation numbers, (epoch, date) pairs, and FELINE index from
consideration. There are enough examples of these indexes performing
poorly.

In contrast, maximum generation numbers and corrected commit
dates both performed quite well. They are frequently the top
two performing indexes, and rarely significantly different.

The trade-off here now seems to be: which _property_ is more important,
locally-computable or backwards-compatible?

* Maximum generation number is backwards-compatible but not
  locally-computable or immutable.

* Corrected commit-date is locally-computable and immutable,
  but not backwards-compatible.

_Editor's Note:_ Every time I think about this trade-off, I can't
come to a hard conclusion about which is better. Instead, I'll
leave that up for discussion.

