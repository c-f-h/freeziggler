# freeziggler

A solver for the FreeCell card game, written in Zig.

The solver is based on the A* algorithm, using a simple "blocked cards" heuristic.

The most significant performance gains come from reducing the number of duplicated, logically equivalent states by
- creating only one move to a free cell or free column, even if several are available
- keeping the free cells sorted
- keeping the columns sorted by their "anchor" card, i.e., the rear-most card in a column

## Building and running

This project currently uses the development version of Zig 0.16.

To run:

    $ zig build run

